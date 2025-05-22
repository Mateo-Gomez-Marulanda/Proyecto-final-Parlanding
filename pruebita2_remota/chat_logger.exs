# Módulo encargado de registrar eventos importantes del chat (login, logout,
# errores, etc.) en un archivo de log llamado "chat_events.log".

defmodule ChatLogger do
  @log_file "chat_events.log"

  # Registra un evento en el archivo de log con timestamp.
  def log(event, data \\ "") do
    timestamp = NaiveDateTime.local_now() |> NaiveDateTime.truncate(:second) |> NaiveDateTime.to_string()
    File.write!(
      @log_file,
      "[#{timestamp}] #{event} #{data}\n",
      [:append]
    )
  end
end
