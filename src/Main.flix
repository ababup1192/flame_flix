def main(): Unit \ { IO, Chan, NonDet } =
    region rc {
        use Flame.{app, port, get, getParam, post, postParam, text, jsonMap, useLogger, fire};

        // In-memory database
        let db: MutMap[String, String, rc] = MutMap.empty(rc);
        let nextId: Ref[Int32, rc] = Ref.fresh(rc, 1);

        app()
            |> Flame.Java.javaServer
            |> port(30000)
            |> useLogger
            |> get("/", _ -> text("Hello"))
            |> get("/ping", _ -> text("pong"))
            |> get("/api/user", _ -> jsonMap(Map#{"name" => "Alice", "age" => "30"}))
            |> getParam("/entry/:id", params ->
                jsonMap(Map#{"your id" => Map.getWithDefault("id", "unknown", params)})
               )
            |> post("/echo", body -> text(body))
            |> post("/api/users", body -> {
                let id = Ref.get(nextId);
                Ref.put(id + 1, nextId);
                let idStr = Int32.toString(id);
                MutMap.put(idStr, body, db);
                jsonMap(Map#{"id" => idStr, "data" => body})
            })
            |> getParam("/api/users/:id", params -> {
                let id = Map.getWithDefault("id", "", params);
                match MutMap.get(id, db) {
                    case Some(data) => jsonMap(Map#{"id" => id, "data" => data})
                    case None => text("Not Found")
                }
            })
            |> fire
    }
