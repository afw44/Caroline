from __future__ import annotations

import os
import datetime as dt
from typing import List, Optional, Dict, Set

from fastapi import FastAPI, HTTPException, Depends, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from sqlalchemy import (
    Column, Integer, String, Date, Float, Text, Table, ForeignKey, create_engine, select, func
)
from sqlalchemy.orm import (
    DeclarativeBase, Mapped, mapped_column, relationship, Session, sessionmaker
)

# --------------------------------------------------------------------
# Database setup (SQLite, file: app.db next to this file)
# --------------------------------------------------------------------

DB_URL = os.getenv("DATABASE_URL", "sqlite:///app.db")
# For SQLite + threadsafety
engine = create_engine(DB_URL, echo=False, future=True, connect_args={"check_same_thread": False} if DB_URL.startswith("sqlite") else {})
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False, future=True)

class Base(DeclarativeBase):
    pass

# Association table Gig<->Gent (many-to-many)
gig_gent = Table(
    "gig_gent",
    Base.metadata,
    Column("gig_id", ForeignKey("gigs.id", ondelete="CASCADE"), primary_key=True),
    Column("gent_id", ForeignKey("gents.id", ondelete="CASCADE"), primary_key=True),
)

class GentORM(Base):
    __tablename__ = "gents"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    username: Mapped[Optional[str]] = mapped_column(String(100), nullable=True, unique=True)
    # future: password_hash, role, etc.

    gigs: Mapped[List["GigORM"]] = relationship(
        secondary=gig_gent, back_populates="gents", lazy="selectin"
    )

class GigORM(Base):
    __tablename__ = "gigs"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    date: Mapped[dt.date] = mapped_column(Date, nullable=False)
    fee: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    notes: Mapped[str] = mapped_column(Text, nullable=False, default="")

    gents: Mapped[List[GentORM]] = relationship(
        secondary=gig_gent, back_populates="gigs", lazy="selectin"
    )

def get_session():
    with SessionLocal() as session:
        yield session

def debug_dump(session: Session):
    print("=== Current DB state ===")
    gents = session.query(GentORM).all()
    gigs  = session.query(GigORM).all()
    print("Gents:")
    for g in gents:
        print(f"  {g.id}: {g.name} ({g.username})")
    print("Gigs:")
    for gig in gigs:
        gent_names = ", ".join([gent.name for gent in gig.gents])
        print(f"  {gig.id}: {gig.title} on {gig.date} fee={gig.fee} gents=[{gent_names}]")
    print("========================")

# --------------------------------------------------------------------
# Pydantic schemas (API I/O) — keep shapes the same as before
# --------------------------------------------------------------------

class Gent(BaseModel):
    id: int
    name: str
    username: Optional[str] = None

class Gig(BaseModel):
    id: int
    title: str
    date: dt.date
    fee: float = 0.0
    notes: str = ""
    gent_ids: List[int] = Field(default_factory=list)

class GigCreate(BaseModel):
    title: str = "New Gig"
    date: dt.date = Field(default_factory=dt.date.today)
    fee: float = 0.0
    notes: str = ""
    gent_ids: List[int] = Field(default_factory=list)

class GigUpdate(BaseModel):
    title: Optional[str] = None
    date: Optional[dt.date] = None
    fee: Optional[float] = None
    notes: Optional[str] = None
    gent_ids: Optional[List[int]] = None

# --------------------------------------------------------------------
# FastAPI app + CORS
# --------------------------------------------------------------------

app = FastAPI(title="Giggle API (SQLite)", version="0.2")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],      # tighten later
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --------------------------------------------------------------------
# Startup: create tables and seed once (if empty)
# --------------------------------------------------------------------

def seed_once(session: Session):
    # If there are already gents, assume we've seeded
    count = session.scalar(select(func.count(GentORM.id)))
    if count and count > 0:
        return

    a = GentORM(name="Alice Archer", username="alice")
    b = GentORM(name="Bobby Banks", username="bobby")
    c = GentORM(name="Charlie Chen", username="charlie")
    d = GentORM(name="Dina Diaz", username="dina")
    session.add_all([a, b, c, d])
    session.flush()  # get ids

    g1 = GigORM(title="Summer Gala",   date=dt.date(2025, 8, 24), fee=1200.0, notes="Black tie.", gents=[a, c])
    g2 = GigORM(title="Park Festival", date=dt.date(2025, 9,  5), fee=800.0,  notes="Outdoor stage.", gents=[b, d])
    g3 = GigORM(title="Private Party", date=dt.date(2025, 9, 12), fee=1500.0, notes="", gents=[a, b, d])

    session.add_all([g1, g2, g3])
    session.commit()

@app.on_event("startup")
def on_startup():
    Base.metadata.create_all(engine)
    with SessionLocal() as s:
        seed_once(s)

# --------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------

def ensure_gent_ids_exist(session: Session, ids: List[int]) -> None:
    if not ids:
        return
    existing_ids = set(id_ for (id_,) in session.execute(select(GentORM.id).where(GentORM.id.in_(ids))))
    missing = sorted(set(ids) - existing_ids)
    if missing:
        raise HTTPException(status_code=400, detail=f"Unknown gent ids: {missing}")

def gig_to_schema(gig: GigORM) -> Gig:
    return Gig(
        id=gig.id,
        title=gig.title,
        date=gig.date,
        fee=gig.fee,
        notes=gig.notes,
        gent_ids=[g.id for g in gig.gents],
    )

# --------------------------------------------------------------------
# Routes (same shapes as your in-memory version)
# --------------------------------------------------------------------

@app.get("/gents", response_model=List[Gent])
def list_gents(session: Session = Depends(get_session)):
    rows = session.scalars(select(GentORM).order_by(GentORM.name)).all()
    return [Gent(id=r.id, name=r.name, username=r.username) for r in rows]

@app.get("/gigs", response_model=List[Gig])
def list_gigs(
    gent_id: Optional[int] = Query(default=None),
    session: Session = Depends(get_session),
):
    if gent_id is None:
        rows = session.scalars(select(GigORM).order_by(GigORM.date)).all()
    else:
        # join on association to filter by gent
        rows = session.scalars(
            select(GigORM)
            .join(gig_gent, gig_gent.c.gig_id == GigORM.id)
            .where(gig_gent.c.gent_id == gent_id)
            .order_by(GigORM.date)
        ).all()
        # Validate gent exists (match previous behavior)
        if not rows and not session.get(GentORM, gent_id):
            raise HTTPException(status_code=404, detail="Gent not found")

    return [gig_to_schema(g) for g in rows]

@app.get("/gigs/{gig_id}", response_model=Gig)
def get_gig(gig_id: int, session: Session = Depends(get_session)):
    gig = session.get(GigORM, gig_id)
    if not gig:
        raise HTTPException(status_code=404, detail="Gig not found")
    return gig_to_schema(gig)

@app.post("/gigs", response_model=Gig, status_code=201)
def create_gig(payload: GigCreate, session: Session = Depends(get_session)):
    ensure_gent_ids_exist(session, payload.gent_ids)
    gig = GigORM(title=payload.title, date=payload.date, fee=payload.fee, notes=payload.notes)
    if payload.gent_ids:
        gig.gents = session.scalars(select(GentORM).where(GentORM.id.in_(payload.gent_ids))).all()
    session.add(gig)
    session.commit()
    session.refresh(gig)
    
    debug_dump(session)
    
    return gig_to_schema(gig)

@app.put("/gigs/{gig_id}", response_model=Gig)
def update_gig(gig_id: int, patch: GigUpdate, session: Session = Depends(get_session)):
    gig = session.get(GigORM, gig_id)
    if not gig:
        raise HTTPException(status_code=404, detail="Gig not found")

    # Partial updates
    if patch.title is not None:
        gig.title = patch.title
    if patch.date is not None:
        gig.date = patch.date
    if patch.fee is not None:
        gig.fee = patch.fee
    if patch.notes is not None:
        gig.notes = patch.notes
    if patch.gent_ids is not None:
        ensure_gent_ids_exist(session, patch.gent_ids)
        gig.gents = session.scalars(select(GentORM).where(GentORM.id.in_(patch.gent_ids))).all()

    session.commit()
    session.refresh(gig)
    
    debug_dump(session)
    
    return gig_to_schema(gig)

# Placeholder for future:
# @app.post("/gigs/{gig_id}/email") ...
