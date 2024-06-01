#####################
### Guard library ###
#####################
guard_source_max_once() {
    local file_name="$(basename "${BASH_SOURCE[0]}")"
    local guard_var="guard_${file_name%.*}" # file_name wo file extension

    [[ "${!guard_var}" ]] && return 1
    [[ "$guard_var" =~ ^[_a-zA-Z][_a-zA-Z0-9]*$ ]] \
        || { echo "Invalid guard: '$guard_var'"; exit 1; }
    declare -gr "$guard_var=true"
}

guard_source_max_once || return 0

#####################
### Library start ###
#####################


###
# Color variables
COLOR_END='\033[0m'

COLOR_DEFAULT='\033[0;39m'
COLOR_DEFAULT_BOLD='\033[1;39m'

COLOR_BLACK='\033[0;30m'
COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[0;33m'
COLOR_BLUE='\033[0;34m'
COLOR_MAGENTA='\033[0;35m'
COLOR_CYAN='\033[0;36m'
COLOR_WHITE='\033[0;37m'

COLOR_BOLD_BLACK='\033[1;30m'
COLOR_BOLD_RED='\033[1;31m'
COLOR_BOLD_GREEN='\033[1;32m'
COLOR_BOLD_YELLOW='\033[1;33m'
COLOR_BOLD_BLUE='\033[1;34m'
COLOR_BOLD_MAGENTA='\033[1;35m'
COLOR_BOLD_CYAN='\033[1;36m'
COLOR_BOLD_WHITE='\033[1;37m'
###

###
# List of functions for usage outside of lib
#
# - define()
# - source_lib()
# - eval_cmd()
# - backtrace()
# - invalid_function_usage()
# - find_path()
# - register_help_text()
# - get_help_text()
###

# For multiline variable definition
#
# Example without evaluation:
# define my_var <<'END_OF_MESSAGE_WITHOUT_EVAL'
# First line
# Second line $var
# END_OF_MESSAGE_WITHOUT_EVAL
#
# Example with evaluation:
# define my_var <<END_OF_MESSAGE_WITH_EVAL
# First line
# Second line $var
# END_OF_MESSAGE_WITH_EVAL
define()
{
    IFS= read -r -d '' "$1" || true
    # Remove the trailing newline
    eval "$1=\${$1%$'\n'}"
}

# Sources library and exits with good info in case of not being able to source
source_lib()
{
    local lib="$1"

    local func_call_file
    func_call_file="$(basename "${BASH_SOURCE[1]}")"

    local error_info
    error_info="File '$func_call_file' requires library '$(basename "$lib")'"

    if ! [[ -f "$lib" ]]
    then
        echo "$error_info"
        echo "Necessary library does not exist: '$lib'"
        exit 1
    fi

    if ! source "$lib"
    then
        echo "$error_info"
        echo "Could not source library even though the file exists: '$lib'"
        exit 1
    fi
}

# Exits and outputs error if command before this fails
eval_cmd()
{
    local exit_code=$?
    (( exit_code == 0 )) && return

    local error_info="$1"

    _validate_input_eval_cmd

    # Update COLUMNS regardless if shopt checkwinsize is enabled
    if [[ -c /dev/tty ]]
    then
        # Pass /dev/tty to the command as if running as background process, the shell
        # is not attached to a terminal
        IFS=' ' read LINES COLUMNS < <(stty size </dev/tty)
    else
        COLUMNS=80
    fi

    local wrapper="$(printf "%.s#" $(seq $COLUMNS))"
    local divider="$(printf "%.s-" $(seq $COLUMNS))"

    define output_message << END_OF_OUTPUT_MESSAGE
${wrapper}
!! Command failed with exit code: $exit_code

Check the command executed right before eval_cmd()

${divider}
Backtrace:
$(backtrace)

${divider}
Error info:

${error_info}

${wrapper}
END_OF_OUTPUT_MESSAGE

    echo "$output_message" >&2
    exit $exit_code
}

_validate_input_eval_cmd()
{

    define function_usage <<END_OF_FUNCTION_USAGE
Usage: eval_cmd <error_info>

Evaluates the previous command's exit code. If non-zero, it will output the 
given <error_info> as well as function backtrace. Exits with the same exit code
as the previous command.

<error_info>: String with information about what command that failed.

Example usage:
    echo hello
    eval_cmd 'Failed to echo'
END_OF_FUNCTION_USAGE

    if [[ -z "$error_info" ]]
    then
        define error_info <<END_OF_FUNCTION_USAGE
Input <error_info> not given.
END_OF_FUNCTION_USAGE

        invalid_function_usage 2 "$function_usage" "$error_info"
        exit 1
    fi
}

get_func_def_line_num()
{
    local func_name=$1
    local script_file=$2

    local output_num

    output_num=$(grep -c "^[\s]*${func_name}()" $script_file)
    (( output_num == 1 )) || { echo '?'; return 1; }

    grep -n "^[\s]*${func_name}()" $script_file | cut -d: -f1
}

backtrace()
{
    # 1 or 0 depending if to include 'backtrace' function in call stack
    # 0 = include 'backtrace' function
    local i_default=1 
    # Top level function name
    local top_level_function='main'

    local iter_part
    local func_name_part
    local line_num_part
    local file_part
    local iter_len
    local func_name_len
    local line_num_len

    local at_part="at"

    local iter_part_template
    local func_name_part_template
    local line_num_part_template
    local file_part_template

    define iter_part_template <<'EOM'
iter_part="#${i}  "
EOM
    define func_name_part_template <<'EOM'
func_name_part="'${FUNCNAME[$i]}' "
EOM
    define line_num_part_template <<'EOM'
line_num_part="  ${BASH_LINENO[$i]}:"
EOM
    define file_part_template <<'EOM'
file_part=" ${BASH_SOURCE[i+1]}"
EOM

    ### Find max lengths
    #
    local i=$i_default
    local iter_maxlen=0
    local func_name_maxlen=0
    local line_num_maxlen=0
    until [[ "${FUNCNAME[$i]}" == "$top_level_function" ]]
    do
        eval "$iter_part_template"
        eval "$func_name_part_template"
        eval "$line_num_part_template"
        eval "$file_part_template"

        iter_len=$(wc -m <<< "$iter_part")
        ((iter_len--))
        func_name_len=$(wc -m <<< "$func_name_part")
        ((func_name_len--))
        line_num_len=$(wc -m <<< "$line_num_part")
        ((line_num_len--))


        ((iter_len > iter_maxlen)) && iter_maxlen=$iter_len
        ((func_name_len > func_name_maxlen)) && func_name_maxlen=$func_name_len
        ((line_num_len > line_num_maxlen)) && line_num_maxlen=$line_num_len

        ((i++))
    done

    ### Construct lines with good whitespacing using max lengths
    #
    local extra_whitespace
    local backtrace_output
    i=$i_default
    until [[ "${FUNCNAME[$i]}" == "$top_level_function" ]]
    do
        eval "$iter_part_template"
        eval "$func_name_part_template"
        eval "$line_num_part_template"
        eval "$file_part_template"

        iter_len=$(wc -m <<< "$iter_part")
        ((iter_len--))

        # Check if to add extra whitespace after 'iter_part'
        if ((iter_len < iter_maxlen))
        then
            local iter_difflen=$((iter_maxlen - iter_len))
            extra_whitespace="$(printf "%.s " $(seq $iter_difflen))"
            iter_part="${iter_part}${extra_whitespace}"
        fi

        func_name_len=$(wc -m <<< "$func_name_part")
        ((func_name_len--))

        # Check if to add extra whitespace after 'func_name_part'
        if ((func_name_len < func_name_maxlen))
        then
            local func_name_difflen=$((func_name_maxlen - func_name_len))
            extra_whitespace="$(printf "%.s " $(seq $func_name_difflen))"
            func_name_part="${func_name_part}${extra_whitespace}"
        fi

        line_num_len=$(wc -m <<< "$line_num_part")
        ((line_num_len--))

        # Check if to add extra whitespace before 'line_num_part'
        if ((line_num_len < line_num_maxlen))
        then
            local line_num_difflen=$((line_num_maxlen - line_num_len))
            extra_whitespace="$(printf "%.s " $(seq $line_num_difflen))"
            line_num_part="${extra_whitespace}${line_num_part}"
        fi

        local line="${iter_part}${func_name_part}${at_part}${line_num_part}${file_part}"

        if [[ -z "$backtrace_output" ]]
        then
            # Before backtrace_output is defined
            backtrace_output="$line"
        else
            printf -v backtrace_output "%s\n${line}" "$backtrace_output"
        fi
        ((i++))
    done
    
    echo "$backtrace_output"
}

invalid_function_usage()
{
    # functions_before=1 represents the function call before this function
    local functions_before=$1
    local function_id_or_usage="$2"
    local error_info="$3"

    # local function_id="$1"
    # local error_info="$2"

    local function_usage
    function_usage=$(get_help_text "$function_id_or_usage")
    local exit_code=$?
    (( exit_code != 0 )) && function_usage="$function_id_or_usage"

    _validate_input_invalid_function_usage "$@"
    # Output: Overrides all the variables when input is invalid

    local func_name="${FUNCNAME[functions_before]}"
    local func_def_file="${BASH_SOURCE[functions_before]}"
    local func_def_line_num="$(get_func_def_line_num $func_name $func_def_file)"
    local func_call_file="${BASH_SOURCE[functions_before+1]}"
    local func_call_line_num="${BASH_LINENO[functions_before]}"

    # Update COLUMNS regardless if shopt checkwinsize is enabled
    if [[ -c /dev/tty ]]
    then
        # Pass /dev/tty to the command as if running as background process, the shell
        # is not attached to a terminal
        IFS=' ' read LINES COLUMNS < <(stty size </dev/tty)
    else
        COLUMNS=80
    fi

    local wrapper="$(printf "%.s#" $(seq $COLUMNS))"
    local divider="$(printf "%.s-" $(seq $COLUMNS))"

    local output_message
    define output_message <<END_OF_VARIABLE_WITH_EVAL

${wrapper}
!! Invalid usage of ${func_name}()

Called from:
${func_call_line_num}: ${func_call_file}
Defined at:
${func_def_line_num}: ${func_def_file}

${divider}
Backtrace:
$(backtrace)

${divider}
Error info:

${error_info}

${divider}
Usage info:

${function_usage}

${wrapper}
END_OF_VARIABLE_WITH_EVAL

    echo "$output_message" >&2
    [[ "$invalid_usage_of_this_func" == 'true' ]] && exit 1
}

# Output:
# Overrides all the variables when input is invalid
# - functions_before
# - function_usage
# - error_info
_validate_input_invalid_function_usage()
{
    local input_functions_before="$1"
    local input_function_usage="$2"
    local input_error_info="$3"

    invalid_usage_of_this_func='false'

    local re='^[0-9]+$'
    if ! [[ $input_functions_before =~ $re ]]
    then
        invalid_usage_of_this_func='true'

        # Remove newlines and spaces to make output better
        input_functions_before=${input_functions_before//[$'\n' ]/}
        # Usage error of this function
        define error_info <<END_OF_ERROR_INFO
Given input <functions_before> is not a number: '$input_functions_before'
END_OF_ERROR_INFO

    elif [[ -z "$input_function_usage" ]]
    then
        invalid_usage_of_this_func='true'

        # Usage error of this function
        define error_info <<END_OF_ERROR_INFO
Given input <function_usage> missing.
END_OF_ERROR_INFO

    elif [[ -z "$input_error_info" ]]
    then
        invalid_usage_of_this_func='true'

        # Usage error of this function
        define error_info <<END_OF_ERROR_INFO
Given input <error_info> missing.
END_OF_ERROR_INFO
    fi

    if [[ "$invalid_usage_of_this_func" == 'true' ]]
    then
        functions_before=0

        # Function usage of this function
        define function_usage <<'END_OF_VARIABLE_WITHOUT_EVAL'
Usage: invalid_function_usage <functions_before> <function_usage> <error_info>
    <functions_before>:
        * Which function to mark as invalid usage.
            - '0': This function: invalid_function_usage()
            - '1': 1 function before this. Which calls invalid_function_usage()
            - '2': 2 functions before this
    <function_usage>:
        * Multi-line description on how to use the function, create multi-line
          variable using define() and pass that variable to the function.
            - Example:

              define function_usage <<'END_OF_VARIABLE'
              Usage: "Function name" <arg1> <arg2>
                  <arg1>:
                      - "arg1 option 1" / "arg1 description"
                  <arg2>:
                      - "arg2 option 1"
                      - "arg2 option 2"
              END_OF_VARIABLE

    <error_info>:
        * Single-/Multi-line with extra info.
            - Example:
              "Invalid input <arg2>: '$arg_two'"
END_OF_VARIABLE_WITHOUT_EVAL
    fi
}

# Only store output in multi-file unique readonly global variables or
# local variables to avoid variable values being overwritten in e.g.
# sourced library files.
# Recommended to always call the function when to use it
find_path()
{
    local to_find="$1"
    local bash_source_array_len="$2"
    shift 2
    local bash_source_array=("$@")

    _validate_input_find_path

    # Set 'source' to resolve until not a symlink
    case "$to_find" in
        'this'|'this_file')
            local file=${bash_source_array[0]}
            ;;
        'last_exec'|'last_exec_file')
            local file=${bash_source_array[-1]}
            ;;
        *)  # Validation already done
    esac

    local path file
    while [ -L "$file" ]; do # resolve until the file is no longer a symlink
        path=$( cd -P "$( dirname "$file" )" &>/dev/null && pwd )
        file=$(readlink "$file")
        # If $file was a relative symlink, we need to resolve it relative
        # to the path where the symlink file was located
        [[ $file != /* ]] && file=$path/$file 
    done
    path=$( cd -P "$( dirname "$file" )" &>/dev/null && pwd )
    file="$path/$(basename "$file")"

    case "$to_find" in
    'this'|'last_exec')
        echo "$path"
        ;;
    'this_file'|'last_exec_file')
        echo "$file"
        ;;
    *)  # Validation already done
        ;;
    esac
}

_validate_input_find_path()
{
    define function_usage <<'END_OF_FUNCTION_USAGE'
Usage: find_path <to_find> <bash_source_array_len> <bash_source_array>
    <to_find>:
        * 'this'
            - Path to this file
        * 'this_file'
            - Path and filename to this file
        * 'last_exec'
            - Path to the latest executed script
            - Example:
                main.sh sources script_1.bash
                script_1.sh executes script_2.sh
                script_2.sh sources  script_3.sh
                script_3.sh calls find_path()
                find_path() outputs path to script_2.bash
        * 'last_exec_file'
            - Path and filename to the latest executed script
            - Example:
                main.sh sources script_1.bash
                script_1.sh executes script_2.sh
                script_2.sh sources  script_3.sh
                script_3.sh calls find_path()
                find_path() outputs path & filname to script_2.bash
    <bash_source_array_len>:
        - Length of ${BASH_SOURCE[@]}
        - "${#BASH_SOURCE[@]}"
    <bash_source_array>:
        - Actual array 
        - "${BASH_SOURCE[@]}"
END_OF_FUNCTION_USAGE

    # Validate <to_find>
    case "$to_find" in
        'this'|'this_file'|'last_exec'|'last_exec_file')
            ;;
        *)
            define error_info <<END_OF_ERROR_INFO
Invalid input <to_find>: '$to_find'
END_OF_ERROR_INFO
            invalid_function_usage 2 "$function_usage" "$error_info"
            exit 1
            ;;
    esac

    # Validate <bash_source_array_len>
    case $bash_source_array_len in
        ''|*[!0-9]*)
define error_info <<END_OF_ERROR_INFO
Invalid input <bash_source_array_len>, not a number: '$bash_source_array_len'
END_OF_ERROR_INFO
            invalid_function_usage 2 "$function_usage" "$error_info"
            exit 1
            ;;
        *)  ;;
    esac

    # Validate <bash_source_array>
    # Use 'bash_source_array_len' to ensure the actual ${BASH_SOURCE[@]} array
    # was passed to the function
    if (( bash_source_array_len != ${#bash_source_array[@]} ))
    then
define error_info <<END_OF_ERROR_INFO
Given length <bash_source_array_len> differs from array length of <bash_source_array>.
    \$bash_source_array_len:   '$bash_source_array_len'
    \${#bash_source_array[@]}: '${#bash_source_array[@]}'
END_OF_ERROR_INFO

        invalid_function_usage 2 "$function_usage" "$error_info"
        exit 1
    fi

    unset function_usage error_info
}

# Arrays to store _handle_args() help text data
_handle_args_registered_help_text_function_ids=()
_handle_args_registered_help_text=()

register_help_text()
{
    local function_id="$1"
    local help_text="$2"

    # Special case for register_help_text(), manually parse for help flag
    _handle_input_register_help_text "$1"

    _validate_input_register_help_text

    _handle_args_registered_help_text_function_ids+=("$function_id")
    _handle_args_registered_help_text+=("$help_text")
}

_handle_input_register_help_text()
{
    define function_usage <<END_OF_FUNCTION_USAGE
Usage: register_help_text <function_id> <help_text>

<function_id>:
    * Each function can have its own set of flags and help text. The function id is used
      for identifying which flags and help text to use. Must be the same function id as
      when registering through register_function_flags().
        - Function id can e.g. be the function name.
<help_text>:
    * Multi-line help text where the first line should have the form like e.g.:
        'register_help_text <function_id> <help_text>'
      Followed by an empty line and thereafter optional multi-line description.
    * Shall not include flag description as that is added automatically using the text
      registered through register_function_flags().
END_OF_FUNCTION_USAGE


    # Manual check as _handle_args() cannot be used, creates circular dependency
    if [[ "$1" == '-h' ]] || [[ "$1" == '--help' ]]
    then
        echo "$function_usage"
        exit 0
    fi
}

_validate_input_register_help_text()
{
    if [[ -z "$function_id" ]]
    then
        define error_info <<END_OF_ERROR_INFO
Given <function_id> is empty.
END_OF_ERROR_INFO
        invalid_function_usage 2 "$function_usage" "$error_info"
        exit 1
    fi

    # Check if function id already registered help text
    for registered in "${_handle_args_registered_help_text_function_ids[@]}"
    do
        if [[ "$function_id" == "$registered" ]]
        then
            define error_info <<END_OF_ERROR_INFO
Given <function_id> have already registered an help text: '$function_id'
END_OF_ERROR_INFO
            invalid_function_usage 2 "$function_usage" "$error_info"
            exit 1
        fi
    done

    if [[ -z "$help_text" ]]
    then
        define error_info <<END_OF_ERROR_INFO
Given <help_text> is empty.
END_OF_ERROR_INFO
        invalid_function_usage 2 "$function_usage" "$error_info"
        exit 1
    fi
}

get_help_text()
{
    local function_id="$1"

    ###
    # Check that <function_id> is registered through register_help_text()
    local function_registered='false'
    for i in "${!_handle_args_registered_help_text_function_ids[@]}"
    do
        local current_function_id="${_handle_args_registered_help_text_function_ids[i]}"
        if [[ "$function_id" == "$current_function_id" ]]
        then
            local registered_help_text="${_handle_args_registered_help_text[i]}"
            function_registered='true'
        fi
    done

    [[ "$function_registered" != 'true' ]] && return 1

    ###
    # Check that <function_id> is registered through register_function_flags()
    local function_registered='false'
    for i in "${!_handle_args_registered_function_ids[@]}"
    do
        if [[ "${_handle_args_registered_function_ids[$i]}" == "$function_id" ]]
        then
            function_registered='true'
            function_index=$i
            break
        fi
    done

    ###
    # Output first part of help text
    echo "Usage: ${registered_help_text}"

    [[ "$function_registered" != 'true' ]] && return 0

    ###
    # Get flags and corresponding descriptions for <function_id>
    local valid_short_options
    local valid_long_options
    local flags_descriptions
    # Convert space separated elements into an array
    IFS='§' read -ra valid_short_options <<< "${_handle_args_registered_function_short_option[function_index]}"
    IFS='§' read -ra valid_long_options <<< "${_handle_args_registered_function_long_option[function_index]}"
    IFS='§' read -ra flags_descriptions <<< "${_handle_args_registered_function_descriptions[function_index]}"

    local array_flag_description_line=()
    local max_line_length=0

    ### 
    # Construct help text lines for each flag & find max line length
    for i in "${!flags_descriptions[@]}"
    do
        local flag_description_line="  "

        # Short flag
        if [[ "${valid_short_options[i]}" != '_' ]]
        then
            flag_description_line+="${valid_short_options[i]}, "
        fi

        # Long flag
        if [[ "${valid_long_options[i]}" != '_' ]]
        then
            flag_description_line+="${valid_long_options[i]}"
        fi
        
        flag_description_line+="   "

        # Find out length
        local line_length=$(wc -m <<< "$flag_description_line")
        (( line_length-- ))
        (( line_length > max_line_length )) && max_line_length=$line_length

        array_flag_description_line+=("$flag_description_line")
    done

    ### 
    # Reconstruct lines with good whitespacing using max line length
    for i in "${!array_flag_description_line[@]}"
    do
        local flag_description_line="${array_flag_description_line[i]}"
        local line_length=$(wc -m <<< "$flag_description_line")
        ((line_length--))

        ###
        # Calculate whitespace for line to line up with maximum length line
        local extra_whitespace=''
        if (( line_length < max_line_length ))
        then
            local diff_length=$((max_line_length - line_length))
            extra_whitespace="$(printf "%.s " $(seq $diff_length))"
        fi

        ###
        # Construct line
        flag_description_line="${flag_description_line}${extra_whitespace}${flags_descriptions[i]}"
        array_flag_description_line[i]="$flag_description_line"
    done

    ###
    # Output flag description lines
    echo
    echo "Flags:"
    for line in "${array_flag_description_line[@]}"
    do
        echo "$line"
    done

    return 0
}

echo_color()
{
    local color="$1"
    shift
    local output="$@"
    printf "${color}%s${COLOR_END}\n" "$output"
}

echo_warning()
{
    echo_color "$COLOR_YELLOW" "$@"
}

echo_error()
{
    echo_color "$COLOR_RED" "$@" >&2
}

echo_highlight()
{
    echo_color "$COLOR_DEFAULT_BOLD" "$@"
}

echo_success()
{
    echo_color "$COLOR_GREEN" "$@"
}

command_exists()
{
    local cmd="$1"

    # 'hash' ignores aliases
    hash "$1" >/dev/null 2>&1
}
