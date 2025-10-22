from fastapi import FastAPI
from pydantic import BaseModel

app = FastAPI()

class Message(BaseModel):
    message: str

@app.get("/api/ping")
def ping():
    return {"status": "ok"}

@app.post("/api/echo")
def echo(msg: Message):
    return {"echo": msg.message}
