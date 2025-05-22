defmodule Util do
  def mostrar_mensaje(mensaje) do
    IO.puts("#{mensaje}")
  end

  def ingresar_texto(mensaje, :texto) do
    mensaje
    |> IO.gets()
    |> String.trim()
  end

  def mostrar_error(mensaje) do
    IO.puts(:standard_error, mensaje)
  end
end
