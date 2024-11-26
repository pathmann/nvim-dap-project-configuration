# nvim-dap-project-configuration
**nvim-dap-project-configuration** is a neovim plugin which acts as configuration provider for [nvim-dap](https://github.com/mfussenegger/nvim-dap) and prelauncher based on a per-project configuration (based on the cwd).

You can use multiple subprojects and select your current (see [Usage](#Usage)).

Optionally you can run your app instead of debugging it with nvim-dap.

## Installation
Install the plugin with your preferred package manager:

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "pathmann/nvim-dap-project-configuration",

  dependencies = {
    "nvim-lua/plenary.nvim",
    "mfussenegger/nvim-dap",
  },

  opts = {
    -- leave empty (to use default settings)
    -- or see the configuration options below
  }
}
```

## Plugin Configuration
These are the default options:

```lua
local defaults = {
  dir = vim.fn.stdpath("state") .. "/dap-project-configuration/", -- path where to store the last selection (depending on the cwd) 
  filename = ".nvim-dap-project-configuration.lua", -- project configuration file to look for in current cwd
  dapcmd = "DapContinue", -- command to run with :ProjectDapRun after the prelaunch tasks are successfully executed (a string is interpreted as vim cmd, a function will be executed)
}
```

## Project configuration
```lua
-- vimcwd/.nvim-dap-project-configuration.lua
return {
    mysubproj1 = {
        prelaunch = { -- these are launched before dapcmd is invoked
            task1 = {
                -- prelaunch task
            }
        },
        dap = { -- this is set as nvim-dap config provider "nvim-dap-project-configuration"
            config1 = {
                -- nvim-dap conifguration1
            },
            config2 = {
                -- nvim-dap configuration_n
            },
        },
        run = {
            launch = "config1", -- will extract run config from dap config "config1", for custom options or if adapter configuration is not compatible, see mysubproj2.run
            output = {
                -- see prelaunch output options
            }
        },
    },
    mysubproj2 = {
        -- ...
        run = {
            launch = {
                cmd = "myexec",
                args = {"progparam1"},
                env = {

                },
            },
            output = {
                -- ...
            }
        }
    }
}
```
If there is only one subproject, it is selected by default.

<details>
<summary>Example project configuration of a QMake subdir project:</summary>

```lua
-- ~/Projects/myproj/.nvim-dap-project-configuration.lua
local projdir = "~/Projects/myproj"
local builddir = "~/Projects/build-myproj"
local workdir = "~/Projects/run-myproj"

return {
  QMake = {
    prelaunch = {
      p1 = {
        cwd = builddir,
        cmd = "qmake",
        args = { projdir },
        output = {
          target = "buffer",
          reuse = true,
          close_on_success = true,
          stop_on_close = true,
        },
        wait = true,
        env = {},
      },
    },
  },
  Make = {
    prelaunch = {
      p1 = {
        cwd = builddir,
        cmd = "make",
        env = {
          PATH = "/usr/local/bin:/usr/bin:/usr/local/sbin",
        },
        wait = true,
        output = {
          target = "buffer",
          close_on_success = false,
          reuse = true,
          autoscroll = true,
          filetype = "qf",
        },
      }
    },
  },
  Clean = {
    prelaunch = {
      p1 = {
        cwd = builddir,
        cmd = "make",
        args = { "clean" },
        env = {
          PATH = "/usr/local/bin:/usr/bin:/usr/local/sbin",
        },
        wait = true,
        output = {
          target = "buffer",
          close_on_success = true,
          autoscroll = true,
          filetype = "qf",
        },
      },
    },
  },
  Subapp1 = {
    prelaunch = {
      p1 = {
        cwd = builddir .. "/src/subapp1",
        cmd = "make",
        env = {
          PATH = "/usr/local/bin:/usr/bin:/usr/local/sbin",
        },
        wait = true,
        output = {
          close_on_success = true,
          autoscroll = true,
        },
      }
    },
    dap = {
      {
        name = "Subapp1",
        type = "gdb",
        request = "launch",
        cwd = workdir .. "/subapp1",
        program = builddir .. "/src/subapp1/subapp1",
        args = {
            "--paramameter1"
        },
      },
    },
  },
  Subapp2 = {
    prelaunch = {
      p1 = {
        cwd = builddir .. "/src/subapp2",
        cmd = "make",
        env = {
          PATH = "/usr/local/bin:/usr/bin:/usr/local/sbin",
        },
        wait = true,
        output = {
          close_on_success = true,
          filetype = "qf",
          autoscroll = true,
        },
      }
    },
    dap = {
      {
        name = "Subapp2",
        type = "gdb",
        request = "launch",
        cwd = workdir .. "/subapp2",
        program = builddir .. "/src/subapp2/subapp2",
        env = {
          DISPLAY = ":0",
        },
      },
    },
  },
  RunSubapp1DebugSubapp2 = {
    prelaunch = {
      p1 = {
        cwd = builddir .. "/src/subapp1",
        cmd = "make",
        env = {
          PATH = "/usr/local/bin:/usr/bin:/usr/local/sbin",
        },
        output = {
          close_on_success = true,
          filetype = "qf",
          autoscroll = true,
        },
        wait = true,
      },
      p2 = {
        cwd = builddir .. "/src/subapp2",
        cmd = "make",
        env = {
          PATH = "/usr/local/bin:/usr/bin:/usr/local/sbin",
        },
        wait = true,
        output = {
          close_on_success = true,
          filetype = "qf",
          autoscroll = true,
        },
      },
      p3 = {
        cwd = workdir .. "/subapp1",
        cmd = builddir .. "/src/subapp1/subapp1",
        args = {"--runparamater"},
        wait = false,
      },
    },
    dap = {
      {
        name = "Subapp2",
        type = "gdb",
        request = "launch",
        cwd = workdir .. "/subapp2",
        program = builddir .. "/src/subapp2",
        env = {
          DISPLAY = ":0",
        },
      },
    }
  },
}
```

So when `RunSubapp1DebugSubapp2` is selected, invoking `ProjectDapRun` would execute `p1`, `p2` and `p3`. The table `dap` is set as dap config provider and `dapcmd` is invoked.
</details>

### Prelaunch
These are the default prelaunch options:
```lua
{
    cwd = cwd, -- working directory of the command
    env = {}, -- table of environment variables
    cmd = nil, -- the command to invoke
    args = {}, -- parameters to pass to cmd
    output = {
        target = "buffer", -- pass all stdout and stderr to a buffer, use "print" to use neovim print function or pass a function(errorstr, datastr) which is invoked
        reuse = true, -- if target == "buffer", reuse the previously opened buffer when rerunning
        close_on_success = false, -- if target == "buffer", close the buffer if the prelaunch was successfull
        stop_on_close = true, -- if target == "buffer", kill the process if the buffer is closed manually
        autoscroll = false, -- if target == "buffer", automatically scroll to end when appending data
    },
    wait = true, -- wait for the command completion and only start the next command or dapcmd if successfull
}
```
Prelaunch tasks are executed sorted by their key.

[plenary.job](https://github.com/nvim-lua/plenary.nvim#plenaryjob) is used to execute prelaunch tasks, see it's documentation for more info.

## Usage
These user commands are available:
- `ProjectDapSelect`: Open the selection popup
- `ProjectDapRun`: Run the selected config
- `ProjectDapCloseSelection`: Close the selection popup (although there is a buffer keymap "q" to close the popup)
- `ProjectDapStopAllTasks`: Stop all prelaunch tasks started by the plugin
- `ProjectDapToggleDap`: Toggles between debugging and running
- `ProjectDapEnableDap`: Enables debugging (disables running)
- `ProjectDapDisableDap`: Disables debugging (enables running)
- `ProjectDapSelectDap`: Open the dap or run popup

## Intention
I was previously working with Qt Creator where you can select the subdir project to run/debug (with configured arguments, etc.). So this plugin was born to adapt this functionality without the need to leave Neovim and/or use a terminal inside Neovim and write bash scripts for all tasks.

I'm pretty sure you could achieve the same goal with another plugin for per-project dap-configs (like [nvim-dap-projects](https://github.com/ldelossa/nvim-dap-projects)) and [overseer.nvim](https://github.com/stevearc/overseer.nvim) for prelaunch tasks, but having it all in one config seems very convenient.

## Improvements
Although the project goal is complete, there are some possible improvements:
- callback possibilities (eg. callback which is ran when selection changes to use different compile_commands.json based on the subproject)
- nested prelaunch tasks to handle some kind of dependency graph but can run some tasks concurrently

