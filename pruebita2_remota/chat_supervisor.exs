# Supervisor encargado de iniciar y monitorear el proceso principal del servidor
# de chat distribuido. Garantiza la tolerancia a fallos reiniciando el servidor

defmodule ChatServerSupervisor do
  use Supervisor

  # Inicia el supervisor y el proceso principal del servidor de chat.
  def start_link(_) do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  # Define la estrategia de supervisión y los hijos supervisados.
  def init(_) do
    children = [
      %{
        id: ChatServerMain,
        start: {Task, :start_link, [fn -> ChatServer.start() end]},
        restart: :permanent
      }
    ]
    Supervisor.init(children, strategy: :one_for_one)
  end
end
