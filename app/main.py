from fastapi import FastAPI
from fastapi.responses import PlainTextResponse

app = FastAPI()


@app.get("/teste", response_class=PlainTextResponse)
@app.get("/prod/teste", response_class=PlainTextResponse)
def teste() -> str:
    return "testado"


@app.get("/health", response_class=PlainTextResponse)
def health() -> str:
    return "ok"
