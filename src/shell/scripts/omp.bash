export POSH_SHELL='bash'
export POSH_SHELL_VERSION=$BASH_VERSION
export POWERLINE_COMMAND='oh-my-posh'
export CONDA_PROMPT_MODIFIER=false
export OSTYPE=$OSTYPE

# disable all known python virtual environment prompts
export VIRTUAL_ENV_DISABLE_PROMPT=1
export PYENV_VIRTUALENV_DISABLE_PROMPT=1

# global variables
_omp_start_time=''
_omp_stack_count=0
_omp_job_count=0
_omp_execution_time=-1
_omp_no_status=true
_omp_status=0
_omp_pipestatus=0
_omp_sigint=''
_omp_executable=::OMP::

# switches to enable/disable features
_omp_cursor_positioning=0
_omp_ftcs_marks=0

# start timer on command start
PS0='${_omp_start_time:0:$((_omp_start_time="$(_omp_start_timer)",0))}$(_omp_ftcs_command_start)'

# set secondary prompt
_omp_secondary_prompt=$(
    "$_omp_executable" print secondary \
        --shell=bash \
        --shell-version="$BASH_VERSION"
)

function _omp_set_cursor_position() {
    # not supported in Midnight Commander
    # see https://github.com/JanDeDobbeleer/oh-my-posh/issues/3415
    if [[ $_omp_cursor_positioning == 0 ]] || [[ -v MC_SID ]]; then
        return
    fi

    local oldstty=$(stty -g)
    stty raw -echo min 0

    local COL
    local ROW
    IFS=';' read -rsdR -p $'\E[6n' ROW COL

    stty "$oldstty"

    export POSH_CURSOR_LINE=${ROW#*[}
    export POSH_CURSOR_COLUMN=${COL}
}

function _omp_start_timer() {
    "$_omp_executable" get millis
}

function _omp_ftcs_command_start() {
    if [[ $_omp_ftcs_marks == 1 ]]; then
        printf '\e]133;C\a'
    fi
}

# template function for context loading
function set_poshcontext() {
    return
}

function _omp_get_primary() {
    # Avoid unexpected expansions when we're generating the prompt below.
    shopt -u promptvars
    trap 'shopt -s promptvars' RETURN

    local prompt
    if shopt -oq posix; then
        # Disable in POSIX mode.
        prompt='[NOTICE: Oh My Posh prompt is not supported in POSIX mode]\n\u@\h:\w\$ '
    else
        prompt=$(
            "$_omp_executable" print primary \
                --save-cache \
                --shell=bash \
                --shell-version="$BASH_VERSION" \
                --status="$_omp_status" \
                --pipestatus="${_omp_pipestatus[*]}" \
                --no-status="$_omp_no_status" \
                --execution-time="$_omp_execution_time" \
                --job-count="$_omp_job_count" \
                --stack-count="$_omp_stack_count" \
                --terminal-width="${COLUMNS-0}" |
                tr -d '\0'
        )
    fi
    echo "${prompt@P}"
}

function _omp_get_secondary() {
    # Avoid unexpected expansions when we're generating the prompt below.
    shopt -u promptvars
    trap 'shopt -s promptvars' RETURN

    if shopt -oq posix; then
        # Disable in POSIX mode.
        echo '> '
    else
        echo "${_omp_secondary_prompt@P}"
    fi
}

function _omp_hook() {
    _omp_status=$? _omp_pipestatus=("${PIPESTATUS[@]}")

    # Ctrl+C入力時に_omp_sigintフラグを立てるためにtrapを登録する。
    #  (PROMPT_COMMANDに_direnv_hookがあるとtrapを毎回クリアするため
    #   _direnv_hookの後に_omp_hookが実行される前提で毎回trapを登録しなおす)
    _omp_install_sigint_trap

    if [[ -v BP_PIPESTATUS && ${#BP_PIPESTATUS[@]} -ge ${#_omp_pipestatus[@]} ]]; then
        _omp_pipestatus=("${BP_PIPESTATUS[@]}")
    fi

    _omp_stack_count=$((${#DIRSTACK[@]} - 1))
    local _omp_jobs=()
    _omp_jobs=($(jobs -p 2>/dev/null))
    _omp_job_count=${#_omp_jobs[@]}

    _omp_execution_time=-1
    _omp_no_status=true  # 本家の対応漏れの補完(zsh流): FTCS/iTerm 統合マークの正確化
    if [[ $_omp_start_time ]]; then
        local omp_now=$("$_omp_executable" get millis)
        _omp_execution_time=$((omp_now - _omp_start_time))
        _omp_no_status=false
    else
        # コマンド未実行(Ctrl+C/空Enter)時は直前の終了ステータスを引き継がない。
        # bashのstatusセグメントは--status(=$?=_omp_status)のみ参照するため直接書き換える。
        if [[ ${_omp_sigint} == "true" ]]; then
            # Ctrl+Cの場合は終了ステータスはSIGINT
            _omp_status=130
        else
            # 空Enterの場合は終了ステータスをクリア
            _omp_status=0
        fi
        _omp_pipestatus=("${_omp_status}")
    fi
    _omp_start_time=''
    _omp_sigint=''

    if [[ ${_omp_pipestatus[-1]} != "$_omp_status" ]]; then
        _omp_pipestatus=("$_omp_status")
    fi

    set_poshcontext
    _omp_set_cursor_position

    PS1='$(_omp_get_primary)'
    PS2='$(_omp_get_secondary)'

    # Ensure that command substitution works in a prompt string.
    shopt -s promptvars

    return $_omp_status
}

function _omp_install_sigint_trap() {
    local trap_cmd='_omp_sigint=true'

    # 既存trapを安全に展開
    local org_trap
    eval "org_trap=($(trap -p SIGINT 2>/dev/null))"

    # 「trap -- 'CMD' SIGINT」のCMD部分を抽出
    local org_trap_cmd="${org_trap[2]-}"

    if [[ -z "${org_trap_cmd}" ]]; then
        # 既存trap無しの場合はtrap_cmdを登録
        trap "${trap_cmd}" SIGINT
    elif [[ "${org_trap_cmd}" == *"${trap_cmd}"* ]]; then
        # trap_cmdが既に登録されている場合は何もしない(二重登録防止)
        :
    else
        # 既存trap有りの場合はtrap_cmdを追加して登録
        trap "${org_trap_cmd}; ${trap_cmd}" SIGINT
    fi
}

function _omp_install_hook() {
    local cmd
    local prompt_command

    for cmd in "${PROMPT_COMMAND[@]}"; do
        # skip initializing when we're already initialized
        if [[ $cmd = _omp_hook ]]; then
            return
        fi

        # check if the command starts with source, if so, do not add it again
        # this is done to avoid issues with sourcing the same file multiple times
        if [[ $cmd = source* ]]; then
            continue
        fi

        prompt_command+=("$cmd")
    done

    # When VS Code shell integration is active, prepend so _omp_hook sets PS1 before
    # VS Code's __vsc_prompt_cmd_original wraps it with A/B shell integration sequences.
    if [[ "${TERM_PROGRAM-}" == "vscode" ]]; then
        PROMPT_COMMAND=(_omp_hook "${prompt_command[@]}")
    else
        PROMPT_COMMAND=("${prompt_command[@]}" _omp_hook)
    fi
}

_omp_install_hook
