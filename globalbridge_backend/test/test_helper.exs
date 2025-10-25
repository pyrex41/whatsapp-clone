# Load environment variables from .env file if it exists
env_file = Path.join(File.cwd!(), ".env")

if File.exists?(env_file) do
  env_file
  |> File.read!()
  |> String.split("\n")
  |> Enum.each(fn line ->
    line = String.trim(line)

    # Skip empty lines and comments
    unless line == "" or String.starts_with?(line, "#") do
      case String.split(line, "=", parts: 2) do
        [key, value] ->
          # Remove quotes if present
          value = String.trim(value, "\"")
          value = String.trim(value, "'")
          System.put_env(key, value)

        _ ->
          :ok
      end
    end
  end)

  IO.puts("✓ Loaded environment variables from .env")
end

Mix.Task.run("ecto.drop", ["--quiet"])
Mix.Task.run("ecto.create", ["--quiet"])
Mix.Task.run("ecto.migrate", ["--quiet"])

ExUnit.start()
