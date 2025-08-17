from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Body, HTTPException
from fastapi.responses import JSONResponse
from typing import Dict, Set, List, Any, Optional
from uuid import uuid4
import re
import asyncio

app = FastAPI()

# ---------- Realtime ----------
connections: Dict[str, Set[WebSocket]] = {}

def add_conn(user_id: str, ws: WebSocket) -> None:
    connections.setdefault(user_id, set()).add(ws)

def remove_conn(user_id: str, ws: WebSocket) -> None:
    if user_id in connections:
        connections[user_id].discard(ws)
        if not connections[user_id]:
            del connections[user_id]

async def send_to_user(user_id: str, payload: dict) -> None:
    for ws in list(connections.get(user_id, [])):
        try:
            await ws.send_json(payload)
        except Exception:
            pass

@app.websocket("/ws")
async def ws_endpoint(ws: WebSocket):
    user_id = ws.query_params.get("user_id")
    if not user_id:
        await ws.close(code=4000)
        return
    await ws.accept()
    add_conn(user_id, ws)
    print("WS CONNECTED:", user_id)
    try:
        while True:
            # keepalive; ignore incoming messages
            await ws.receive_text()
    except WebSocketDisconnect:
        remove_conn(user_id, ws)
        print("WS DISCONNECTED:", user_id)

@app.get("/health")
def health():
    return {"ok": True}

# ---------- Gigs (in-memory) ----------
GENTS: List[str] = ["gent-1", "gent-2", "gent-3", "gent-4", "gent-5"]

# gigs store: id -> {id, date, client_email, fee}
gigs: Dict[str, Dict[str, Any]] = {}

# assignments: gig_id -> set(gent-ids)
gig_assignments: Dict[str, Set[int]] = {}

_email_rx = re.compile(r"^[^@]+@[^@]+\.[^@]+$")

def ensure_gig(gig_id: str) -> Dict[str, Any]:
    g = gigs.get(gig_id)
    if not g:
        raise HTTPException(status_code=404, detail="gig not found")
    return g

@app.post("/gigs", status_code=201)
def create_gig(
    assigned_ids: Set[int] = Body(set(), embed=True),
    date: str = Body(..., embed=True),
    client_email: str = Body(..., embed=True),
    fee: int = Body(..., embed=True),
    notes: str = Body("", embed=True)
):
    if not _email_rx.match(client_email):
        raise HTTPException(status_code=400, detail="invalid email")
    gid = str(uuid4())
    gigs[gid] = {
        "id": gid, "date": date, "client_email": client_email,
        "fee": fee, "notes": notes, "assigned_ids": set(assigned_ids)
    }
    gig_assignments[gid] = set(assigned_ids)   # ← keep what client sent
    return JSONResponse(content={**gigs[gid], "assigned_ids": sorted(list(assigned_ids))}, status_code=201)
    
    
@app.get("/gigs")
def list_gigs():
    out = []
    for gid, g in gigs.items():
        ids = g.get("assigned_ids", set())
        out.append({**g, "assigned_ids": sorted(list(ids))})
    return {"gigs": out}
from fastapi.responses import JSONResponse
import asyncio

@app.patch("/gigs/{gig_id}")
async def update_gig(
    gig_id: str,
    date: Optional[str] = Body(None, embed=True),
    client_email: Optional[str] = Body(None, embed=True),
    fee: Optional[int] = Body(None, embed=True),
    notes: Optional[str] = Body(None, embed=True),
    assigned_ids: Optional[Set[int]] = Body(None, embed=True),
):
    g = ensure_gig(gig_id)

    if date is not None:
        g["date"] = date
    if client_email is not None:
        if not _email_rx.match(client_email):
            raise HTTPException(status_code=400, detail="invalid email")
        g["client_email"] = client_email
    if fee is not None:
        g["fee"] = fee
    if notes is not None:
        g["notes"] = notes
    if assigned_ids is not None:
        g["assigned_ids"] = set(assigned_ids)
        gig_assignments[gig_id] = set(assigned_ids)

        # kick notifications on the running loop
        tasks = []
        for gent_idx in assigned_ids:
            if 0 <= gent_idx < len(GENTS):
                gent_user_id = GENTS[gent_idx]
                tasks.append(asyncio.create_task(
                    send_to_user(gent_user_id, {"type": "gigs_changed"})
                ))
        if tasks:
            await asyncio.gather(*tasks, return_exceptions=True)

    # normalize response: assigned_ids as a list
    ids = g.get("assigned_ids", set())
    payload = {**g, "assigned_ids": sorted(list(ids))}
    return JSONResponse(content=payload, status_code=200)
    

@app.get("/manager/gigs")
def manager_gigs():
    return list_gigs()

@app.get("/gent/{gent_id}/gigs")
def gigs_for_gent(gent_id: str):
    if gent_id not in GENTS:
        raise HTTPException(status_code=404, detail="unknown gent id")
    gent_idx = GENTS.index(gent_id)  # map string -> index

    result: List[Dict[str, Any]] = []
    for gid, g in gigs.items():
        ids = g.get("assigned_ids", set())
        if gent_idx in ids:
            result.append(g)
    result.sort(key=lambda x: (x.get("date", ""), x["id"]))
    return {"gigs": result}


"""
source .venv/bin/activate
uvicorn app:app --reload --host 127.0.0.1 --port 8000
"""
