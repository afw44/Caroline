from __future__ import annotations

import os
import datetime as dt
from typing import List, Optional

from fastapi import FastAPI, HTTPException, Depends, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from sqlalchemy import (
    Column, Integer, String, Date, Float, Text, Table, ForeignKey, create_engine, select, func, UniqueConstraint
)
from sqlalchemy.orm import (
    DeclarativeBase, Mapped, mapped_column, relationship, Session, sessionmaker
)

from enum import Enum

# --------------------------------------------------------------------
# DB
# --------------------------------------------------------------------
DB_URL = os.getenv("DATABASE_URL", "sqlite:///app.db")
engine = create_engine(
    DB_URL,
    echo=False,
    future=True,
    connect_args={"check_same_thread": False} if DB_URL.startswith("sqlite") else {},
)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False, future=True)

class Base(DeclarativeBase):
    pass

# M2M
gig_gent = Table(
    "gig_gent",
    Base.metadata,
    Column("gig_id", ForeignKey("gigs.id", ondelete="CASCADE"), primary_key=True),
    Column("gent_id", ForeignKey("gents.id", ondelete="CASCADE"), primary_key=True),
)

# Enum
class Phase(str, Enum):
    planning  = "planning"
    booked    = "booked"
    completed = "completed"

class AvailabilityStatus(str, Enum):
    no_reply   = "no_reply"
    available  = "available"
    unavailable= "unavailable"
    assigned   = "assigned"

class AvailabilityORM(Base):
    __tablename__ = "availability"
    id: Mapped[int]        = mapped_column(Integer, primary_key=True, autoincrement=True)
    gig_id: Mapped[int]    = mapped_column(ForeignKey("gigs.id", ondelete="CASCADE"), nullable=False)
    gent_id: Mapped[int]   = mapped_column(ForeignKey("gents.id", ondelete="CASCADE"), nullable=False)
    status: Mapped[str]    = mapped_column(String(20), nullable=False, default=AvailabilityStatus.no_reply.value)

    __table_args__ = (UniqueConstraint("gig_id", "gent_id", name="uq_avail_gig_gent"),)

# ORM models
class GentORM(Base):
    __tablename__ = "gents"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    username: Mapped[Optional[str]] = mapped_column(String(100), nullable=True, unique=True)

    gigs: Mapped[List["GigORM"]] = relationship(
        secondary=gig_gent, back_populates="gents", lazy="selectin"
    )

class GigORM(Base):
    __tablename__ = "gigs"
    id: Mapped[int]       = mapped_column(Integer, primary_key=True, autoincrement=True)
    title: Mapped[str]    = mapped_column(String(200), nullable=False)
    date: Mapped[dt.date] = mapped_column(Date, nullable=False)
    fee:  Mapped[float]   = mapped_column(Float, nullable=False, default=0.0)
    notes: Mapped[str]    = mapped_column(Text,  nullable=False, default="")
    # store enum as TEXT for SQLite portability
    phase: Mapped[str]    = mapped_column(String(20), nullable=False, default=Phase.planning.value)

    gents: Mapped[List[GentORM]] = relationship(
        secondary=gig_gent, back_populates="gigs", lazy="selectin"
    )

def get_session():
    with SessionLocal() as session:
        yield session

def debug_dump(session: Session):
    print("=== Current DB state ===")
    for g in session.query(GentORM).all():
        print(f"Gent {g.id}: {g.name} ({g.username})")
    for gig in session.query(GigORM).all():
        gent_names = ", ".join([gent.name for gent in gig.gents])
        print(f"Gig {gig.id}: {gig.title} on {gig.date} fee={gig.fee} phase={gig.phase} gents=[{gent_names}]")
    print("========================")

# --------------------------------------------------------------------
# Schemas
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
    phase: Phase = Phase.planning
    gent_ids: List[int] = Field(default_factory=list)

class GigCreate(BaseModel):
    title: str = "New Gig"
    date: dt.date = Field(default_factory=dt.date.today)
    fee: float = 0.0
    notes: str = ""
    phase: Phase = Phase.planning
    gent_ids: List[int] = Field(default_factory=list)

class GigUpdate(BaseModel):
    title: Optional[str] = None
    date: Optional[dt.date] = None
    fee: Optional[float] = None
    notes: Optional[str] = None
    phase: Optional[Phase] = None
    gent_ids: Optional[List[int]] = None

class AvailabilityEntry(BaseModel):
    gent_id: int
    status: AvailabilityStatus

class AvailabilityUpdate(BaseModel):
    gent_id: int
    status: AvailabilityStatus


# --------------------------------------------------------------------
# App + CORS
# --------------------------------------------------------------------
app = FastAPI(title="Giggle API (SQLite)", version="0.3")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --------------------------------------------------------------------
# Startup (tables + migration + seed)
# --------------------------------------------------------------------
def seed_once(session: Session):
    if session.scalar(select(func.count(GentORM.id))) or 0 > 0:
        return
    a = GentORM(name="Alice Archer", username="alice")
    b = GentORM(name="Bobby Banks", username="bobby")
    c = GentORM(name="Charlie Chen", username="charlie")
    d = GentORM(name="Dina Diaz", username="dina")
    session.add_all([a, b, c, d])
    session.flush()

    g1 = GigORM(title="Summer Gala",   date=dt.date(2025, 8, 24), fee=1200.0, notes="Black tie.",         phase=Phase.booked.value,    gents=[a, c])
    g2 = GigORM(title="Park Festival", date=dt.date(2025, 9,  5), fee=800.0,  notes="Outdoor stage.",     phase=Phase.planning.value,  gents=[b, d])
    g3 = GigORM(title="Private Party", date=dt.date(2025, 9, 12), fee=1500.0, notes="",                    phase=Phase.completed.value, gents=[a, b, d])
    session.add_all([g1, g2, g3])
    session.commit()

@app.on_event("startup")
def startup():
    Base.metadata.create_all(engine)
    # --- lightweight migrations for SQLite ---
    if DB_URL.startswith("sqlite"):
        with engine.begin() as conn:
            # gigs.phase column (you already have this)
            cols = [r[1] for r in conn.exec_driver_sql("PRAGMA table_info(gigs);")]
            if "phase" not in cols:
                conn.exec_driver_sql("ALTER TABLE gigs ADD COLUMN phase TEXT NOT NULL DEFAULT 'planning';")

            # availability table (create if not exists)
            conn.exec_driver_sql("""
                CREATE TABLE IF NOT EXISTS availability (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    gig_id INTEGER NOT NULL REFERENCES gigs(id) ON DELETE CASCADE,
                    gent_id INTEGER NOT NULL REFERENCES gents(id) ON DELETE CASCADE,
                    status TEXT NOT NULL DEFAULT 'no_reply',
                    CONSTRAINT uq_avail_gig_gent UNIQUE (gig_id, gent_id)
                );
            """)
    with SessionLocal() as s:
        seed_once(s)

# --------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------

def ensure_gent_ids_exist(session: Session, ids: List[int]) -> None:
    if not ids:
        return
    existing_ids = {id_ for (id_,) in session.execute(select(GentORM.id).where(GentORM.id.in_(ids)))}
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
        phase=Phase(gig.phase),
        gent_ids=[g.id for g in gig.gents],
    )
    
def sync_assignment_with_availability(session: Session, gig: GigORM, gent_id: int, status: AvailabilityStatus):
    gent = session.get(GentORM, gent_id)
    if gent is None:
        return
    is_member = any(g.id == gent_id for g in gig.gents)
    if status == AvailabilityStatus.assigned and not is_member:
        gig.gents.append(gent)
    if status != AvailabilityStatus.assigned and is_member:
        gig.gents = [g for g in gig.gents if g.id != gent_id]


# --------------------------------------------------------------------
# Routes
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
        # Manager view: all gigs
        rows = session.scalars(
            select(GigORM).order_by(GigORM.date, GigORM.title)
        ).all()
        return [gig_to_schema(g) for g in rows]

    # Validate gent exists (even though planning gigs are public)
    if not session.get(GentORM, gent_id):
        raise HTTPException(status_code=404, detail="Gent not found")

    # Gent view:
    #  - include ALL planning gigs
    #  - include booked/completed gigs only if assigned
    rows = session.scalars(
        select(GigORM)
        .outerjoin(gig_gent, gig_gent.c.gig_id == GigORM.id)
        .where(
            (GigORM.phase == Phase.planning.value) |
            (gig_gent.c.gent_id == gent_id)
        )
        .distinct()  # avoid dupes if multiple joins ever happen
        .order_by(GigORM.date, GigORM.title)
    ).all()

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
    gig = GigORM(
        title=payload.title,
        date=payload.date,
        fee=payload.fee,
        notes=payload.notes,
        phase=payload.phase.value,
    )
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

    if patch.title is not None: gig.title = patch.title
    if patch.date  is not None: gig.date  = patch.date
    if patch.fee   is not None: gig.fee   = patch.fee
    if patch.notes is not None: gig.notes = patch.notes
    if patch.phase is not None: gig.phase = patch.phase.value
    if patch.gent_ids is not None:
        ensure_gent_ids_exist(session, patch.gent_ids)
        gig.gents = session.scalars(select(GentORM).where(GentORM.id.in_(patch.gent_ids))).all()

    session.commit()
    session.refresh(gig)
    debug_dump(session)
    return gig_to_schema(gig)

@app.get("/gigs/{gig_id}/availability", response_model=List[AvailabilityEntry])
def get_availability(gig_id: int, session: Session = Depends(get_session)):
    gig = session.get(GigORM, gig_id)
    if not gig:
        raise HTTPException(status_code=404, detail="Gig not found")

    # Build map gent_id -> status (default no_reply)
    statuses = { (gid,): AvailabilityStatus.no_reply.value for (gid,) in session.execute(select(GentORM.id)) }

    # Overlay existing availability rows for this gig
    rows = session.execute(
        select(AvailabilityORM.gent_id, AvailabilityORM.status).where(AvailabilityORM.gig_id == gig_id)
    ).all()
    for gid, st in rows:
        statuses[(gid,)] = st

    # Return entries for all gents, sorted by gent name
    gent_rows = session.scalars(select(GentORM).order_by(GentORM.name)).all()
    out: List[AvailabilityEntry] = []
    for g in gent_rows:
        out.append(AvailabilityEntry(gent_id=g.id, status=AvailabilityStatus(statuses[(g.id,)])))
    return out

@app.put("/gigs/{gig_id}/availability", response_model=AvailabilityEntry)
def set_availability(
    gig_id: int,
    payload: AvailabilityUpdate,
    actor_role: str = Query(..., pattern="^(manager|gent)$"),
    actor_gent_id: Optional[int] = Query(default=None),
    session: Session = Depends(get_session),
):
    gig = session.get(GigORM, gig_id)
    if not gig:
        raise HTTPException(status_code=404, detail="Gig not found")

    # Validate actors / permissions
    if actor_role == "gent":
        if actor_gent_id is None or actor_gent_id != payload.gent_id:
            raise HTTPException(status_code=403, detail="Gents can only update their own availability")
        if payload.status == AvailabilityStatus.assigned:
            raise HTTPException(status_code=403, detail="Only managers can assign")
    else:
        # manager: ok
        pass

    # Upsert availability row
    avail = session.scalar(
        select(AvailabilityORM).where(
            AvailabilityORM.gig_id == gig_id,
            AvailabilityORM.gent_id == payload.gent_id
        )
    )
    if avail is None:
        avail = AvailabilityORM(gig_id=gig_id, gent_id=payload.gent_id, status=payload.status.value)
        session.add(avail)
    else:
        avail.status = payload.status.value

    # Keep assignment list in sync with 'assigned'
    sync_assignment_with_availability(session, gig, payload.gent_id, payload.status)

    session.commit()
    session.refresh(gig)  # in case membership changed

    return AvailabilityEntry(gent_id=payload.gent_id, status=payload.status)


@app.delete("/gigs/{gig_id}", status_code=204)
def delete_gig(
    gig_id: int,
    actor_role: str = Query(..., pattern="^(manager)$"),
    session: Session = Depends(get_session),
):
    gig = session.get(GigORM, gig_id)
    if not gig:
        raise HTTPException(status_code=404, detail="Gig not found")
    session.delete(gig)
    session.commit()
    return Response(status_code=204)
