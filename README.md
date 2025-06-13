-----

## 🚀 Bash-CLI Framework: 您的下一代 Bash 命令行接口工具

Bash-CLI 是一个强大、模块化且易于使用的 Bash 命令行接口 (CLI) 框架，旨在简化复杂的 Bash 脚本开发，使其更具可维护性和可扩展性。它支持命令注册、参数解析、灵活的标志处理、自动帮助生成以及子命令结构，让您的 Bash 脚本像专业工具一样。

### ✨ 核心特性

  * **命令注册与组织**: 轻松定义顶级命令和多层级子命令（例如 `user add`），使您的 CLI 结构清晰。
  * **灵活的参数和标志处理**:
      * 支持长标志 (`--flag-name`) 和短标志 (`-f`)。
      * 支持带值的标志（`--flag value` 或 `--flag=value`）。
      * 支持布尔型标志（`--enable-feature`，默认 `true`）。
      * 支持必填标志和默认值。
      * 自动解析位置参数。
  * **智能帮助文档生成**: 根据注册的命令和标志自动生成详细、美观的帮助信息，包括用法、描述、可用命令和标志列表。
  * **模块化设计**: 将每个命令的代码分离到单独的文件中，方便团队协作和代码维护。
  * **代码生成工具**: 内置 `bash-cli.sh` 生成器，帮助您快速初始化项目和创建新的命令文件，并自动更新主脚本的引入。
  * **无需子目录的子命令**: 支持 `command.subcommand` 这种扁平化的命令文件结构（例如 `commands/user.add.sh`），而非 `commands/user/add.sh`，简化文件管理。
  * **命令文件权限管理**: 确保主脚本在添加新的命令源文件后仍然保持可执行权限。
  * **对 `bash-cli.sh` 工具本身的帮助支持**: 您可以直接运行 `bash-cli.sh --help` 来获取生成器工具的使用说明。
  * **`add` 命令的智能主脚本识别**: `bash-cli.sh add` 命令在不指定 `--main-script` 时，会自动尝试识别当前目录下最可能的主 CLI 脚本，提高便利性。

-----

### 📦 安装与快速开始

1.  **下载框架文件**:
    将 `bash-cli.sh` 文件下载到您的项目根目录。

    ```bash
    curl -o bash-cli.sh https://raw.githubusercontent.com/snail2sky/bash-cli/main/bash-cli.sh 
    chmod +x bash-cli.sh
    ```

2.  **初始化新项目**:
    使用 `bash-cli.sh` 生成器初始化您的 CLI 项目。这将创建您的主 CLI 脚本（例如 `mycli.sh`）和 `commands/` 目录，其中包含 `root.sh`。

    ```bash
    ./bash-cli.sh init mycli.sh
    # 这将创建 mycli.sh 和 commands/root.sh
    ```

3.  **运行您的 CLI**:
    尝试运行您新创建的 CLI。

    ```bash
    ./mycli.sh --help
    # 或者直接
    ./mycli.sh
    ```

-----

### 🛠️ 使用示例

#### 1\. 创建新命令

要创建一个名为 `user` 的新命令：

```bash
./bash-cli.sh add user --main-script mycli.sh
# 或者，如果 mycli.sh 在当前目录且是唯一的CLI主脚本，可以省略 --main-script
./bash-cli.sh add user
```

这将在 `commands/` 目录下创建一个 `user.sh` 文件。其内容如下：

```bash
#!/bin/bash

# Function for the 'user' command.
cli_user_func() {
    echo "Executing command: user"
    echo "Positional arguments: $@"

    # 示例：访问全局标志
    # local verbose_global=$(cli_get_global_flag "verbose")
    # if [[ "$verbose_global" == "true" ]]; then
    #     echo "Verbose output enabled."
    # fi
}

# Register the 'user' command.
cli_register_command \
    "user" \
    "cli_user_func" \
    "Manage user accounts." \
    "This command provides subcommands to manage user accounts, including adding, deleting, and listing users." \
    "${CLI_TOOL_NAME} user [command] [flags]"

# 示例：为 'user' 命令注册一个本地标志
# cli_register_flag \
#     "user" \
#     "dry-run" \
#     "d" \
#     "false" \
#     "Perform a dry run without making changes." \
#     "bool" \
#     "false"
```

#### 2\. 添加子命令

要为 `user` 命令添加一个名为 `add` 的子命令（即 `user add`）：

```bash
./bash-cli.sh add user.add --main-script mycli.sh
# 同样，也可以省略 --main-script 让其自动检测
./bash-cli.sh add user.add
```

这将在 `commands/` 目录下创建一个 `user.add.sh` 文件。其内容如下：

```bash
#!/bin/bash

# Function for the 'user.add' command.
cli_user_add_func() {
    echo "Executing command: user.add"
    echo "Positional arguments: $@"

    # 获取名为 'username' 的位置参数
    local username="${1:-}" # 第一个位置参数
    if [[ -z "$username" ]]; then
        echo -e "${CLI_COLOR_RED}Error: Username is required.${CLI_COLOR_RESET}" >&2
        cli_display_help "user.add"
        return 1
    fi
    echo "Adding user: $username"

    # 示例：获取标志值
    # local force_creation=$(cli_get_flag "force")
    # if [[ "$force_creation" == "true" ]]; then
    #     echo "Forcing user creation."
    # fi
}

# Register the 'user.add' command.
cli_register_command \
    "user.add" \
    "cli_user_add_func" \
    "Add a new user to the system." \
    "This command creates a new user account with specified details. Requires a username as the first positional argument." \
    "${CLI_TOOL_NAME} user add <username> [--force]"

# 示例：为 'user.add' 命令注册一个本地标志
cli_register_flag \
    "user.add" \
    "force" \
    "f" \
    "false" \
    "Force user creation even if user exists." \
    "bool" \
    "false"

cli_register_flag \
    "user.add" \
    "email" \
    "e" \
    "" \
    "Email address for the new user." \
    "string" \
    "false"
```

#### 3\. 运行命令和访问参数/标志

在您的 `mycli.sh` 中引入新创建的命令（如果 `bash-cli.sh add` 自动添加了就无需手动操作）：

```bash
# mycli.sh
# ...
source "$(dirname "$0")/commands/user.sh"
source "$(dirname "$0")/commands/user.add.sh"
# ...
cli_run "$@"
```

现在您可以运行这些命令了：

```bash
./mycli.sh user add bob --email bob@example.com -f
# Output:
# Executing command: user.add
# Positional arguments: bob
# Adding user: bob
# Forcing user creation. # 如果您在 cli_user_add_func 中取消了注释并使用了该标志
```

获取帮助信息：

```bash
./mycli.sh user --help
# 这将显示 'user' 命令的帮助，包括其子命令 'add'。

./mycli.sh user add --help
# 这将显示 'user.add' 命令的详细帮助，包括其标志。
```

-----

### 📝 重构与维护注意事项

在重构和维护基于 Bash-CLI 的项目时，请考虑以下几点：

1.  **版本兼容性**: Bash-CLI 框架需要 **Bash 4.x 或更高版本**。在项目开始时或环境部署时，务必检查 Bash 版本。
2.  **命令命名约定**:
      * 使用小写字母和连字符（`-`）或点（`.`）来命名命令（例如 `my-command`, `user.add`）。
      * 对应的函数名建议使用 `cli_command_path_func` 的形式（例如 `cli_user_add_func`）。
3.  **模块化组织**:
      * 将每个命令的代码放在其自己的 `.sh` 文件中，例如 `commands/my-command.sh`。
      * 子命令使用点分隔符对应文件名，例如 `user.add` 命令的文件名为 `commands/user.add.sh`。
      * 在主 CLI 脚本（例如 `mycli.sh`）中，按需 `source` 这些命令文件。建议将 `root.sh` 放在最前面。
4.  **清晰的帮助信息**:
      * 在 `cli_register_command` 中提供清晰的 `short_description` 和 `long_description`。
      * 为每个命令及其标志提供 `example` 用法，这会直接显示在帮助输出中。
      * 为每个标志提供有意义的 `description`。
5.  **参数和标志的访问**:
      * **位置参数**直接通过 `$1`, `$2` 等在命令函数中访问，或者通过 `"$@"` 访问所有参数。
      * **标志值**应始终通过 `cli_get_flag "flag_name"` 或 `cli_get_global_flag "flag_name"` 来获取，而不是直接访问 `$1` 或 `$2`。这能确保正确处理解析后的值，包括默认值。
6.  **错误处理与退出**:
      * 在命令函数内部，当发生错误时，使用 `echo -e "${CLI_COLOR_RED}Error: ...${CLI_COLOR_RESET}" >&2` 将错误信息输出到标准错误。
      * 错误发生后，通常应调用 `exit 1` 来表示程序非正常退出，或者 `return 1` 让当前函数返回失败状态。
      * 如果需要显示特定命令的帮助，可以调用 `cli_display_help "command.path"`。
7.  **`source` 路径管理**:
      * 使用 `source "$(dirname "$0")/bash-cli.sh"` 确保框架文件能被正确引入，无论主脚本在哪里被调用。
      * 同样，在主脚本中引入命令文件时，使用 `source "$(dirname "$0")/${commands_dir}/command.sh"` 这种相对路径，以提高项目的可移植性。
8.  **变量命名**:
      * 框架内部变量统一使用 `CLI_` 前缀，以避免与用户脚本中的变量名冲突。
      * 在您的命令函数中，建议使用 `local` 关键字声明变量，防止变量污染全局作用域。
9.  **调试**:
      * 利用 `echo` 语句进行调试，特别是在解析参数和标志的复杂逻辑中。
      * 使用 `set -x` 可以在脚本执行时打印所有命令，帮助追踪执行流程（在生产环境中谨慎使用）。
10. **代码风格与规范**:
      * 遵循一致的 Bash 编码风格，例如 [ShellCheck](https://www.shellcheck.net/) 工具可以帮助您检查语法错误和潜在问题。
      * 保持代码缩进和格式的统一，提高可读性。
      * 添加充分的注释来解释复杂逻辑和命令用途。

通过遵循这些指南，您将能够构建出健壮、可维护且用户友好的 Bash CLI 应用程序。

-----
