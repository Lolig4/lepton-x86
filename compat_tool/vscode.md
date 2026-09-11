# Attaching to an application via vscode:

Forward the port to the machine running vscode.
```
ssh -L 1337:localhost:1337 steamos@device # or adb forward tcp:1337 tcp:1337
```

Launch your application.
```
lepton start application_name
```

Use the following configuration for VSCode with CodeLLDB (after installing the
CodeLLDB extension):

```
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Attach to android apk (CodeLLDB)",
      "type": "lldb",
      "request": "attach",
      "pid": 1000,
      "processCreateCommands": [
        "gdb-remote localhost:1337"
      ],
    }
  ]
}
```

It requires a PID argument, but it can be arbitrary, since we attach to the
application directly ourselves next using the command:

```
lepton lldb_server instance_or_application_name
```

Or for LLDB-DAP use (after installing the extension):
```
{
  "version": "0.2.0",
  "configurations": [
    {
        "name": "Attach to android apk (LLDB-DAP)",
        "type": "lldb-dap",
        "request": "attach",
        "gdb-remote-port": 1337,
    }
  ]
}
```

And also execute the above lldb_server command.
Next press play on the "Attach to android apk (...)" button in VSCode to start
debugging.

