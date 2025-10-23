from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from fastapi import APIRouter

# Set root_path to handle proxy prefix properly
app = FastAPI()

class Message(BaseModel):
    message: str

# Remove the prefix from router since root_path handles it
router = APIRouter()

@router.get("/ping")
def ping():
    return {"status": "ok"}

@router.post("/echo")
def echo(msg: Message):
    return {"echo": msg.message}

app.include_router(router)

# --- last-resort catch-all handler ---
@app.middleware("http")
async def catch_all(request: Request, call_next):
    response = await call_next(request)
    if response.status_code == 404:
        return JSONResponse(
            status_code=404,
            content={
                "error": "Route not found",
                "requested_url": str(request.url),
                "path": request.url.path,
                "root_path": request.scope.get("root_path", "")
                
            },
        )
    return response
