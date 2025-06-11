# bash-cli - 简洁强大的 Bash 命令行框架

`bash-cli` 是一个轻量级、健壮且高度模块化的 Bash 命令行工具框架，旨在极大地简化 Bash 脚本中复杂 CLI 工具的开发。它支持直观的子命令结构（如 `serve.start`）、全面的 Flag 处理（包括短 Flag、长 Flag、带值 Flag、布尔 Flag 和必需 Flag），并能自动生成清晰的帮助信息，让你的命令行工具更具专业性。

### 核心特性

* **直观的命令层级**: 通过点分隔符 (`.`) 轻松定义多级子命令，例如 `mycli serve` 或 `mycli serve.start`。
* **全面的 Flag 支持**:
    * **短 Flag**: 如 `-v` (verbose)。
    * **长 Flag**: 如 `--verbose`。
    * **带值的 Flag**: 如 `--port 8080` 或 `--port=8080`。
    * **布尔 Flag**: 仅存在即为 `true` (如 `--background`)。
    * **默认值**: 为 Flag 设置预设值。
    * **必需 Flag**: 强制用户提供某些关键 Flag。
* **全局 Flag**: 支持在任何命令之前或之后传递的全局 Flag，其值在整个 CLI 应用生命周期中有效。
* **自动帮助生成**: 自动为命令和 Flag 生成详细且易读的帮助信息。
* **模块化设计**: 鼓励将命令逻辑封装在独立的 Bash 函数中，提高代码可维护性和可读性。
* **简洁的 API**: 提供清晰的 API 来注册命令、Flag 和获取 Flag 值，降低学习成本。

### 文件结构

* `bash-cli.sh`: `bash-cli` 框架的核心实现文件。
* `mycli.sh`: 一个使用 `bash-cli` 构建的示例 CLI 工具，展示了如何注册和使用命令及 Flag。

### 快速开始

#### 1. 获取 `bash-cli`

将 `bash-cli.sh` 和你的主脚本（例如 `mycli.sh`）放在同一目录下。

#### 2. 赋予执行权限

确保你的脚本具有执行权限：

```bash
chmod +x mycli.sh bash-cli.sh
```

#### 3. 运行示例

尝试运行附带的示例 CLI 工具：

```bash
./mycli.sh
```

### 构建你的 CLI 工具

使用 `bash-cli` 开发命令行工具非常直接。

#### 3.1. 引入框架

在你的主脚本 (例如 `mycli.sh`) 的开头，通过 `source` 命令引入 `bash-cli.sh`：

```bash
#!/bin/bash

# 引入 bash-cli 核心框架
source "$(dirname "$0")/bash-cli.sh"

# ... 你的命令和 Flag 注册
```

#### 3.2. 注册命令 (`cli_register_command`)

每个命令行命令都对应一个 Bash 函数。使用 `cli_register_command` 来注册你的命令及其对应的函数。

```bash
cli_register_command \
    <用户命令路径> \
    <对应函数名> \
    <短描述> \
    [长描述 (可选)] \
    [使用示例 (可选)]
```

* **`<用户命令路径>`**: 用户在命令行中输入的命令层级。
    * **根命令**: 使用空字符串 `""`。
    * **一级子命令**: 例如 `"serve"`。
    * **多级子命令**: 使用点分隔符，例如 `"serve.start"`。
* **`<对应函数名>`**: 当此命令被调用时，框架会执行的 Bash 函数名。
* **`<短描述>`**: 在 `help` 信息中显示的简要描述。
* `[长描述]`: (可选) 更详细的描述，将在 `help` 命令中显示。
* `[使用示例]`: (可选) 命令的典型使用示例，方便用户快速理解。

**示例:**

```bash
# 根命令函数
cli_root_func() {
    echo "Welcome to my CLI tool!"
}
# 注册根命令 (用户命令路径为 "")
cli_register_command \
    "" \
    "cli_root_func" \
    "A simple CLI tool example."

# `serve` 子命令函数
cli_serve_func() {
    echo "Serving application..."
}
# 注册 `serve` 命令 (用户命令路径为 "serve")
cli_register_command \
    "serve" \
    "cli_serve_func" \
    "Start the server."

# `serve.start` 子命令函数
cli_serve_start_func() {
    echo "Starting server in background."
}
# 注册 `serve.start` 命令 (用户命令路径为 "serve.start")
cli_register_command \
    "serve.start" \
    "cli_serve_start_func" \
    "Start the server process in the background."
```

#### 3.3. 注册 Flag (`cli_register_flag` / `cli_register_global_flag`)

为你的命令定义可以接受的 Flag。Flag 可以是全局的，也可以是命令特定的。

```bash
cli_register_flag \
    <用户命令路径> \
    <长 Flag 名称> \
    <短 Flag 字符 (或空)> \
    <默认值> \
    <描述> \
    <类型 (string|bool)> \
    [是否必需 (true|false)]
```

* **`<用户命令路径>`**: Flag 所属的命令路径。
    * **全局 Flag**: 使用空字符串 `""`。
    * **命令特定 Flag**: 使用该命令的用户命令路径 (例如 `"serve"` 或 `"serve.start"`)。
* **`<长 Flag 名称>`**: Flag 的完整名称，例如 `verbose` (用户输入 `--verbose`)。
* **`<短 Flag 字符>`**: Flag 的单字符别名，例如 `v` (用户输入 `-v`)。如果不需要短 Flag，请留空 `""`。
* **`<默认值>`**: 如果用户未在命令行中提供此 Flag，将使用的预设值。
* **`<描述>`**: 在 `help` 信息中显示的 Flag 描述。
* **`<类型>`**: Flag 值的预期数据类型，可以是 `string` (字符串) 或 `bool` (布尔)。
* `[是否必需]`: (可选) `true` 或 `false`。如果设置为 `true` 且用户未提供该 Flag，CLI 将报错并显示帮助。默认为 `false`。

**注册全局 Flag 的快捷函数**:

为了方便注册全局 Flag，你可以使用 `cli_register_global_flag` 函数，它与 `cli_register_flag ""` 的作用是相同的。

```bash
cli_register_global_flag \
    <长 Flag 名称> \
    <短 Flag 字符 (或空)> \
    <默认值> \
    <描述> \
    <类型 (string|bool)> \
    [是否必需 (true|false)]
```

**示例:**

```bash
# 注册全局 Flag (使用快捷函数)
cli_register_global_flag "debug" "D" "false" "Enable global debug logging." "bool"
cli_register_global_flag "config" "c" "" "Path to configuration file." "string"

# 注册 `serve` 命令的本地 Flag
cli_register_flag "serve" "port" "p" "8000" "Port to listen on." "string"
cli_register_flag "serve" "host" "" "127.0.0.1" "Host to bind to." "string"

# 注册 `serve.start` 命令的本地 Flag (包含一个必需 Flag)
cli_register_flag "serve.start" "background" "b" "false" "Run in background (daemonize)." "bool"
cli_register_flag "serve.start" "env" "e" "development" "Deployment environment (e.g., prod, dev)." "string" "true" # 必需 Flag
```

#### 3.4. 获取 Flag 值 (`cli_get_flag` / `cli_get_global_flag`)

在你的命令函数内部，你可以使用提供的函数来获取已解析的 Flag 值。

* `cli_get_flag <Flag 名称>`: 这是获取 Flag 值的推荐方法。它会自动根据当前命令上下文的优先级来返回 Flag 值（优先本地 Flag，其次全局 Flag）。
* `cli_get_global_flag <Flag 名称>`: 如果你明确需要获取一个**被定义为全局的 Flag 的值**，并且希望忽略任何同名的本地 Flag 可能存在的覆盖，可以使用此函数。

**示例:**

```bash
# 在命令函数中
cli_root_func() {
    local verbose=$(cli_get_flag "verbose")       # 获取全局 Flag "verbose" 的值
    local config_path=$(cli_get_flag "config")     # 获取全局 Flag "config" 的值
    local global_debug=$(cli_get_global_flag "debug") # 明确获取全局 Flag "debug" 的值

    if [[ "$verbose" == "true" ]]; then echo "Verbose mode enabled."; fi
    if [[ -n "$config_path" ]]; then echo "Using config file: $config_path"; fi
    if [[ "$global_debug" == "true" ]]; then echo "Global debug is ON."; fi
}

cli_serve_func() {
    local port=$(cli_get_flag "port") # 获取 `serve` 命令的本地 Flag "port" 的值
    local debug_setting=$(cli_get_flag "debug") # 获取当前上下文的 `debug` Flag 值 (可能是全局的)
    echo "Serving on port: $port (Debug: $debug_setting)"
}
```

#### 3.5. 运行 CLI 逻辑

最后，在你的主脚本末尾调用 `cli_run` 函数，传入所有命令行参数，`bash-cli` 将接管解析和分派任务：

```bash
# --- 运行 CLI ---
cli_run "$@"
```

### 详细使用示例

假设你的主脚本名为 `mycli.sh`。

#### 根命令和全局 Flag

```bash
# 运行根命令，不带任何 Flag
./mycli.sh
# 预期输出:
# Welcome to my CLI tool!
# Use 'mycli.sh help' for more information.

# 运行根命令，带全局 Flag
./mycli.sh -D
# 预期输出:
# Global debug mode is ON (retrieved via cli_get_global_flag).
# Welcome to my CLI tool!
# Use 'mycli.sh help' for more information.

./mycli.sh --config /path/to/my.conf
# 预期输出:
# Using config file: /path/to/my.conf
# Welcome to my CLI tool!
# Use 'mycli.sh help' for more information.

# 运行根命令，带多个全局 Flag
./mycli.sh -D -c /tmp/app.conf
# 预期输出:
# Global debug mode is ON (retrieved via cli_get_global_flag).
# Using config file: /tmp/app.conf
# Welcome to my CLI tool!
# Use 'mycli.sh help' for more information.
```

#### 子命令和本地 Flag

```bash
# 运行 `serve` 命令，使用默认端口
./mycli.sh serve
# 预期输出:
# Serving on 127.0.0.1:8000...
# Remaining arguments for serve:

# 运行 `serve` 命令，指定端口和主机
./mycli.sh serve --port 9000 --host 0.0.0.0
# 预期输出:
# Serving on 0.0.0.0:9000...
# Remaining arguments for serve:

# 运行 `serve.start` 命令，带本地 Flag 和全局 Flag
./mycli.sh serve.start -D --background -e production
# 预期输出:
# [Serve Start] Global debug mode is ON (retrieved via cli_get_global_flag).
# Starting server in background: true
# Logging to file:
# Environment: production
# Remaining arguments for 'serve start':
```

#### 帮助信息

```bash
# 查看根命令帮助
./mycli.sh help
# 或
./mycli.sh --help
# 或
./mycli.sh -h

# 查看 `serve` 命令帮助
./mycli.sh help serve
# 或
./mycli.sh serve --help

# 查看 `serve.start` 命令帮助
./mycli.sh help serve.start
# 或
./mycli.sh serve.start --help
```

#### 错误处理 (必需 Flag 缺失)

```bash
# 运行 `serve.start` 命令，但缺少必需的 `env` Flag
./mycli.sh serve.start --background
# 预期输出:
# Error: Required flag --env not set for command context 'root serve start'.
# Usage:
#   mycli.sh serve.start [flags]
#   mycli.sh serve.start [command]
# ... (以及 serve.start 命令的帮助信息)
```

---
