# Definimos un módulo llamado Cookie
defmodule Cookie do
  # Definimos una constante para la longitud de la llave (en bytes)
  @longitud_llave 128

  # Función principal del módulo
  def main() do
    # Genera una secuencia de bytes aleatorios de longitud @longitud_llave
    :crypto.strong_rand_bytes(@longitud_llave)
    # Codifica los bytes aleatorios en base64 para que sean legibles como texto
    |> Base.encode64()
    # Llama a la función mostrar_mensaje del módulo Util para mostrar el resultado
    |> Util.mostrar_mensaje()
  end
end

# Ejecuta la función principal del módulo Cookie
Cookie.main()
