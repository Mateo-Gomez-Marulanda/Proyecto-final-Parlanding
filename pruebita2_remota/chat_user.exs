# Modulos de cliente para el chat

Code.require_file("util.ex", __DIR__)

defmodule ChatClient do
  def start() do
    Node.connect(:'servidor@192.168.100.7')
    :timer.sleep(500)

    {username, _password} = autenticar_usuario()

    server = :global.whereis_name(:chat_server)
    if server == :undefined do
      Util.mostrar_error("No se encontró el servidor de chat. ¿Está corriendo?")
    else
      send(server, {:register, self(), username})
      receive do
        {:registered, ^username} ->
          Util.mostrar_mensaje("\n¡BIENVENIDO A EL SISTEMA DE CHAT, #{username}!\n\n ▶ Escribe /salir para salir de la sala actual.\n ▶ Escribe /create <nombre_sala> para crear una sala.\n ▶ Escribe /join <nombre_sala> para unirte a una sala.\n ▶ Escribe /list para ver usuarios conectados.\n ▶ Escribe /history para ver el historial de la sala. \n ▶ Escribe /buscar <criterio> <valor> para buscar en el historial (usuario, palabra, fecha).\n ▶ Escribe /salas para ver las salas disponibles.\n ▶ Escribe /ayuda para ver la lista de comandos.\n ▶ Escribe /privado <usuario> <mensaje> para enviar un mensaje privado a un usuario.\n\n")
          Util.mostrar_mensaje("\n───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────")
          chat_loop(server, username)
      end
    end
  end

  # Autenticación de usuario
  defp autenticar_usuario() do
    path = "usuarios.csv"
    File.write!(path, "", [:append]) # Crea el archivo si no existe

    Util.mostrar_mensaje("¡Bienvenido al sistema de chat!. Inicia sesión o registrate si no tienes cuenta:")

    username = Util.ingresar_texto("\nUsuario: ", :texto)
    password = Util.ingresar_texto("Contraseña: ", :texto)

    case buscar_usuario(path, username, password) do
      :ok ->
        Util.mostrar_mensaje("\n¡Inicio de sesión exitoso!\n")
        {username, password}
      :no_user ->
        Util.mostrar_mensaje("\nUsuario no encontrado. ¿Deseas registrarte? (si/no)")
        resp = String.downcase(Util.ingresar_texto("> ", :texto))
        if resp == "si" do
          File.write!(path, "#{username},#{password}\n", [:append])
          Util.mostrar_mensaje("\n¡Usuario registrado exitosamente!\n")
          {username, password}
        else
          autenticar_usuario()
        end
      :wrong_pass ->
        Util.mostrar_error("\nContraseña incorrecta. Intenta de nuevo.\n")
        autenticar_usuario()
    end
  end

  # Busca el usuario en el archivo CSV
  defp buscar_usuario(path, username, password) do
    File.stream!(path)
    |> Enum.map(&String.trim/1)
    |> Enum.find_value(:no_user, fn linea ->
      case String.split(linea, ",", parts: 2) do
        [u, p] when u == username and p == password -> :ok
        [u, _] when u == username -> :wrong_pass
        _ -> false
      end
    end)
  end

  # Bucle de chat
  # que espera mensajes del servidor y del usuario
  defp chat_loop(server, username) do
    input_pid = self()
    spawn(fn ->
      msg = Util.ingresar_texto("> ", :texto)
      send(input_pid, {:user_input, msg})
    end)
    receive do
      {:user_input, msg} ->
        cond do
          msg == "/salir" ->
            send(server, {:salir_sala, self()})
            receive do
              {:cambiado_a_global} ->
                Util.mostrar_mensaje("\nSaliste de la sala y volviste a la sala global.")
                chat_loop(server, username)
              {:desconectado} ->
                IO.write("\e[H\e[2J") # Limpiar terminal
                Util.mostrar_mensaje("Has cerrado sesión. Inicia sesión para continuar:\n")
                start()
            end
          String.starts_with?(msg, "/create ") ->
            [_cmd, sala] = String.split(msg, " ", parts: 2)
            send(server, {:create_sala, self(), sala})
            chat_loop(server, username)
          String.starts_with?(msg, "/join ") ->
            [_cmd, sala] = String.split(msg, " ", parts: 2)
            send(server, {:join_sala, self(), sala})
            chat_loop(server, username)
          msg == "/list" ->
            send(server, {:list, self()})
            chat_loop(server, username)
          msg == "/history" ->
            send(server, {:history, self()})
            chat_loop(server, username)
          String.starts_with?(msg, "/buscar ") ->
            case String.split(msg, " ", parts: 3) do
              ["/buscar", criterio, valor] when criterio in ["usuario", "palabra", "fecha"] and valor != "" ->
                send(server, {:buscar, self(), criterio, valor})
              _ ->
                Util.mostrar_mensaje("[INFO] Uso correcto: /buscar <usuario|palabra|fecha> <valor>")
            end
            chat_loop(server, username)
          msg == "/salas" ->
            send(server, {:salas, self()})
            chat_loop(server, username)
          msg == "/ayuda" ->
            send(server, {:ayuda, self()})
            chat_loop(server, username)
          String.starts_with?(msg, "/privado ") ->
            resto = String.trim_leading(msg, "/privado ")
            case String.split(resto, " ", parts: 2) do
              [usuario, mensaje] when mensaje != nil and mensaje != "" ->
                send(server, {:privado, self(), usuario, mensaje})
              _ ->
                Util.mostrar_mensaje("[INFO] Uso correcto: /privado <usuario con espacios> <mensaje>")
            end
            chat_loop(server, username)
          msg != "" ->
            send(server, {:message, self(), msg})
            chat_loop(server, username)
          true ->
            chat_loop(server, username)
        end
      {:chat, from, msg, sala} ->
        Util.mostrar_mensaje("[#{sala}] #{from}: #{msg}")
        chat_loop(server, username)
      {:privado, from, mensaje} ->
        Util.mostrar_mensaje("[PRIVADO de #{from}]: #{mensaje}")
        chat_loop(server, username)
      {:info, info} ->
        Util.mostrar_mensaje("[INFO] #{info}")
        chat_loop(server, username)
      _ ->
        chat_loop(server, username)
    end
  end
end

ChatClient.start()
