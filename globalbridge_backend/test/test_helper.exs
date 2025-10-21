Mix.Task.run("ecto.drop", ["--quiet"])
Mix.Task.run("ecto.create", ["--quiet"])
Mix.Task.run("ecto.migrate", ["--quiet"])

ExUnit.start()
