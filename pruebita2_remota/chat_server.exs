# Módulo principal del servidor de chat distribuido. Gestiona usuarios,
# salas, mensajes, historial, búsquedas y comandos especiales.

Code.require_file("util.ex", __DIR__)
Code.require_file("chat_logger.exs", __DIR__)

defmodule ChatServer do

  #  Inicia el servidor de chat, registra el proceso globalmente y arranca el loop principal.
  def start() do
    :global.register_name(:chat_server, self())
    Util.mostrar_mensaje("Servidor de chat iniciado.")
    loop(%{}, %{"global" => MapSet.new()})
  end

  # Loop principal del servidor, maneja los mensajes entrantes y actualiza el estado.
  defp loop(users, salas) do
    receive do

      # Registro de usuario en el chat global
      {:register, pid, username} ->
        Util.mostrar_mensaje("#{username} se ha unido al chat global.")
        users = Map.put(users, pid, %{username: username, sala: "global"})
        salas = Map.update!(salas, "global", &MapSet.put(&1, pid))
        send(pid, {:registered, username})
        broadcast(users, salas, "global", "#{username} se ha unido al chat.", from: "Sistema")
        loop(users, salas)
        ChatLogger.log("LOGIN", username)


      # Manejo de mensajes de usuario a la sala
      {:message, pid, msg} ->
        %{username: username, sala: sala} = Map.get(users, pid)
        guardar_historial(sala, username, msg)
        broadcast(users, salas, sala, msg, from: username)
        loop(users, salas)

      # Manejo de mensajes privados entre usuarios
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

      # Manejo de búsquedas avanzadas en el historial
      {:buscar, pid, criterio, valor} ->
        user = Map.get(users, pid)
        if user do
          sala = user.sala
          resultados = buscar_en_historial(sala, criterio, valor)
          send(pid, {:info, "Resultados de búsqueda en '#{sala}' por #{criterio}=#{valor}:\n" <> resultados})
        else
          send(pid, {:info, "No estás registrado."})
          ChatLogger.log("ERROR", "Búsqueda fallida: usuario no registrado")
        end
        loop(users, salas)

      # Manejo de desconexiones de usuario / loggout
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
        if user, do: ChatLogger.log("LOGOUT", user.username)

      # Creación de nuevas salas de chat
      {:create, pid, sala} ->
        if Map.has_key?(salas, sala) do
          send(pid, {:info, "La sala '#{sala}' ya existe."})
          loop(users, salas)
        else
          nuevas_salas = Map.put(salas, sala, MapSet.new())
          send(pid, {:info, "Sala '#{sala}' creada. Usa /join #{sala} para unirte."})
          loop(users, nuevas_salas)
        end

      # Unirse a una sala existente
      {:create_sala, pid, sala} ->
        if Map.has_key?(salas, sala) do
          send(pid, {:info, "La sala '#{sala}' ya existe."})
          loop(users, salas)
        else
          nuevas_salas = Map.put(salas, sala, MapSet.new())
          send(pid, {:info, "Sala '#{sala}' creada. Usa /join #{sala} para unirte."})
          loop(users, nuevas_salas)
        end

      # Unirse a una sala existente
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

      # Listar usuarios en la sala actual
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

      # Listar todas las salas existentes
      {:salas, pid} ->
        lista_salas = Map.keys(salas) |> Enum.join(", ")
        send(pid, {:info, "Salas existentes: #{lista_salas}"})
        loop(users, salas)

       # Comando de ayuda
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
        /buscar <criterio> <valor> → Buscar en el historial por usuario, palabra o fecha.
        /privado <usuario> <mensaje> → Enviar mensaje privado a un usuario.
        /salir                → Salir de la sala actual
        ───────────────────────────────────────────────
        """
        send(pid, {:info, ayuda})
        loop(users, salas)

      # Comando de historial
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

      # Comando de salir de la sala actual
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

  # Búsqueda avanzada en historial
  defp buscar_en_historial(sala, criterio, valor) do
    path = "historial_#{sala}.csv"
    if File.exists?(path) do
      File.read!(path)
      |> String.split("\n", trim: true)
      |> Enum.filter(fn linea ->
        case String.split(linea, ",", parts: 3) do
          [fecha, user, mensaje] ->
            case criterio do
              "usuario" -> String.downcase(user) == String.downcase(valor)
              "fecha" -> String.starts_with?(fecha, valor)
              "palabra" -> String.contains?(String.downcase(mensaje), String.downcase(valor))
              _ -> false
            end
          _ -> false
        end
      end)
      |> Enum.map(fn linea ->
        case String.split(linea, ",", parts: 3) do
          [fecha, user, mensaje] -> "[#{fecha}] #{user}: #{mensaje}"
          _ -> ""
        end
      end)
      |> Enum.join("\n")
      |> (fn s -> if s == "", do: "No se encontraron resultados.", else: s end).()
    else
      "No hay mensajes en esta sala."
    end
  end

  # Envía mensajes a todos los usuarios en la sala especificada
  defp broadcast(_users, salas, sala, msg, from: from) do
    Enum.each(Map.get(salas, sala, MapSet.new()), fn pid ->
      send(pid, {:chat, from, msg, sala})
    end)
  end


end

ChatServer.start()
