# Flame

A lightweight web framework for [Flix](https://flix.dev/) with effect polymorphism.

> **Note:** This is an experimental project exploring web framework design in Flix.

## Features

- **Type-safe state transitions** - `NoServer` → `WithServer` phantom types ensure `fire()` is only callable when a server is configured
- **Effect polymorphism** - Route handlers can have arbitrary effects that compose automatically
- **Pluggable server backends** - Server implementation is injected via `Flame.server()`, making it easy to swap backends or use mocks for testing
- **Middleware support** - Logger middleware with request/response hooks via algebraic effects
- **URL parameter extraction** - Pattern matching with `:param` syntax (e.g., `/users/:id`)

## Quick Start

```flix
def main(): Unit \ { IO, Chan, NonDet } =
    use Flame.{app, port, get, post, text, jsonMap, useLogger, fire};

    app()
        |> Flame.Java.javaServer
        |> port(8080)
        |> useLogger
        |> get("/", _ -> text("Hello, Flame!"))
        |> get("/ping", _ -> text("pong"))
        |> post("/echo", body -> text(body))
        |> fire
```

## Example with URL Parameters and State

```flix
def main(): Unit \ { IO, Chan, NonDet } =
    region rc {
        use Flame.{app, port, get, getParam, post, text, jsonMap, useLogger, fire};

        let db: MutMap[String, String, rc] = MutMap.empty(rc);
        let nextId: Ref[Int32, rc] = Ref.fresh(rc, 1);

        app()
            |> Flame.Java.javaServer
            |> port(30000)
            |> useLogger
            |> get("/", _ -> text("Hello"))
            |> get("/api/user", _ -> jsonMap(Map#{"name" => "Alice", "age" => "30"}))
            |> getParam("/entry/:id", params ->
                jsonMap(Map#{"your id" => Map.getWithDefault("id", "unknown", params)})
            )
            |> post("/api/users", body -> {
                let id = Ref.get(nextId);
                Ref.put(id + 1, nextId);
                let idStr = Int32.toString(id);
                MutMap.put(idStr, body, db);
                jsonMap(Map#{"id" => idStr, "data" => body})
            })
            |> fire
    }
```

## Sample Output

```
$ flix run
Server running on http://localhost:30000
[GET] / --> Request
[GET] / <-- text/plain; charset=UTF-8 (1ms)
[GET] /ping --> Request
[GET] /ping <-- text/plain; charset=UTF-8 (0ms)
[POST] /echo --> Request
[POST] /echo <-- text/plain; charset=UTF-8 (0ms)
[GET] /entry/42 --> Request
[GET] /entry/42 <-- application/json; charset=UTF-8 (1ms)
```

## Pluggable Server & Testability

The server implementation is decoupled from the app configuration. You can inject any server backend via `Flame.server()`:

```flix
// Production: use Java HttpServer
app() |> Flame.Java.javaServer |> fire

// Testing: use a mock server that exits immediately
def mockServer(_data: Flame.AppData[{}]): Unit \ { IO, Chan, NonDet } =
    unchecked_cast(() as _ \ { IO, Chan, NonDet })

app() |> Flame.server(mockServer) |> fire
```

This design enables:
- **Easy testing** - Verify state transitions and route configuration without starting a real server
- **Backend flexibility** - Swap server implementations (e.g., Jetty, Netty) without changing app code
- **Type safety** - The compiler ensures `fire()` is only called after a server is configured

## Building

```bash
flix build
flix run
```

## Running Tests

```bash
flix test
```

## License

MIT License - see [LICENSE.md](LICENSE.md)
