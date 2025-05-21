Code.require_file("util.ex", __DIR__)

defmodule ChatServer do
  def start() do
    :global.register_name(:chat_server, self())
    Util.mostrar_mensaje("Servidor de chat iniciado.")
    loop(%{}, %{"global" => MapSet.new()})
  end

  defp loop(users, salas) do
    receive do
      {:register, pid, username} ->
        Util.mostrar_mensaje("#{username} se ha unido al chat global.")
        users = Map.put(users, pid, %{username: username, sala: "global"})
        salas = Map.update!(salas, "global", &MapSet.put(&1, pid))
        send(pid, {:registered, username})
        broadcast(users, salas, "global", "#{username} se ha unido al chat.", from: "Sistema")
        loop(users, salas)

      {:message, pid, msg} ->
        %{username: username, sala: sala} = Map.get(users, pid)
        guardar_historial(sala, username, msg)
        broadcast(users, salas, sala, msg, from: username)
        loop(users, salas)

      {:privado, pid, destinatario, mensaje} ->
        user = Map.get(users, pid)
        case Enum.find(users, fn {_k, v} -> v.username == destinatario end) do
          {dest_pid, _} when dest_pid != pid ->
            send(dest_pid, {:privado, user.username, mensaje})
            send(pid, {:info, "Mensaje privado enviado a #{destinatario}."})
          _ ->
            send(pid, {:info, "El usuario '#{destinatario}' no existe o eres tú mismo."})
        end
        loop(users, salas)

      {:disconnect, pid} ->
        user = Map.get(users, pid)
        users = Map.delete(users, pid)
        salas = if user do
          Map.update!(salas, user.sala, &MapSet.delete(&1, pid))
        else
          salas
        end
        if user, do: broadcast(users, salas, user.sala, "#{user.username} ha salido del chat.", from: "Sistema")
        send(pid, {:desconectado})
        loop(users, salas)

      {:create_sala, pid, sala} ->
        if Map.has_key?(salas, sala) do
          send(pid, {:info, "La sala '#{sala}' ya existe."})
          loop(users, salas)
        else
          nuevas_salas = Map.put(salas, sala, MapSet.new())
          send(pid, {:info, "Sala '#{sala}' creada. Usa /join #{sala} para unirte."})
          loop(users, nuevas_salas)
        end

      {:join_sala, pid, sala} ->
        user = Map.get(users, pid)
        cond do
          user == nil ->
            send(pid, {:info, "No estás registrado."})
            loop(users, salas)
          not Map.has_key?(salas, sala) ->
            send(pid, {:info, "La sala '#{sala}' no existe. Usa /create #{sala} para crearla."})
            loop(users, salas)
          true ->
            salas = Map.update!(salas, user.sala, &MapSet.delete(&1, pid))
            salas = Map.update!(salas, sala, &MapSet.put(&1, pid))
            users = Map.put(users, pid, %{user | sala: sala})
            send(pid, {:info, "Te uniste a la sala '#{sala}'."})
            broadcast(users, salas, sala, "#{user.username} se ha unido a la sala.", from: "Sistema")
            loop(users, salas)
        end

      {:list, pid} ->
        user = Map.get(users, pid)
        if user do
          sala = user.sala
          usuarios = for {_, %{username: uname, sala: ^sala}} <- users, do: uname
          send(pid, {:info, "Usuarios en sala '#{sala}': #{Enum.join(usuarios, ", ")}"})
        else
          send(pid, {:info, "No estás registrado."})
        end
        loop(users, salas)

      {:salas, pid} ->
        lista_salas = Map.keys(salas) |> Enum.join(", ")
        send(pid, {:info, "Salas existentes: #{lista_salas}"})
        loop(users, salas)

      {:ayuda, pid} ->
        ayuda = """
        \nCOMANDOS DISPONIBLES:
        ───────────────────────────────────────────────
        /ayuda                → Ver este menú de ayuda.
        /salas                → Listar todas las salas existentes.
        /list                 → Mostrar usuarios conectados en tu sala.
        /create <sala>        → Crear una nueva sala de chat.
        /join <sala>          → Unirse a una sala de chat.
        /history              → Consultar historial de mensajes de la sala.
        /privado <usuario> <mensaje> → Enviar mensaje privado a un usuario.
        /salir                → Salir de la sala actual
        ───────────────────────────────────────────────
        """
        send(pid, {:info, ayuda})
        loop(users, salas)

      {:history, pid} ->
        user = Map.get(users, pid)
        if user do
          sala = user.sala
          historial = leer_historial(sala)
          send(pid, {:info, "Historial de '#{sala}':\n" <> historial})
        else
          send(pid, {:info, "No estás registrado."})
        end
        loop(users, salas)

      {:salir_sala, pid} ->
        user = Map.get(users, pid)
        if user do
          sala_actual = user.sala
          if sala_actual == "global" do
            # Desconectar completamente
            users = Map.delete(users, pid)
            salas = Map.update!(salas, "global", &MapSet.delete(&1, pid))
            broadcast(users, salas, "global", "#{user.username} ha salido del chat.", from: "Sistema")
            send(pid, {:desconectado})
            loop(users, salas)
          else
            # Sacar de la sala actual y mandar a global
            salas = Map.update!(salas, sala_actual, &MapSet.delete(&1, pid))
            salas = Map.update!(salas, "global", &MapSet.put(&1, pid))
            users = Map.put(users, pid, %{user | sala: "global"})
            send(pid, {:cambiado_a_global})
            broadcast(users, salas, sala_actual, "#{user.username} ha salido de la sala.", from: "Sistema")
            broadcast(users, salas, "global", "#{user.username} ha vuelto a la sala global.", from: "Sistema")
            loop(users, salas)
          end
        else
          send(pid, {:info, "No estás registrado."})
          loop(users, salas)
        end
    end
  end

  # Guarda el historial en la carpeta actual con fecha/hora
  defp guardar_historial(sala, username, msg) do
    timestamp = NaiveDateTime.local_now() |> NaiveDateTime.truncate(:second) |> NaiveDateTime.to_string()
    File.write!(
      "historial_#{sala}.csv",
      "#{timestamp},#{username},#{msg}\n",
      [:append]
    )
  end

  # Lee el historial en la carpeta actual
  defp leer_historial(sala) do
    path = "historial_#{sala}.csv"
    if File.exists?(path) do
      File.read!(path)
      |> String.split("\n", trim: true)
      |> Enum.map(fn linea ->
        case String.split(linea, ",", parts: 3) do
          [fecha, user, mensaje] -> "[#{fecha}] #{user}: #{mensaje}"
          _ -> ""
        end
      end)
      |> Enum.join("\n")
    else
      "No hay mensajes en esta sala."
    end
  end

  defp broadcast(_users, salas, sala, msg, from: from) do
    Enum.each(Map.get(salas, sala, MapSet.new()), fn pid ->
      send(pid, {:chat, from, msg, sala})
    end)
  end
end

ChatServer.start()
