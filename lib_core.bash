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
# List of global definitions - Functions, variables, arrays
#
#   define()
#
#   get_func_def_line_num()
#   is_short_flag()
#   is_long_flag()
#   get_long_flag_var_name()
#   valid_var_name()
#
#   backtrace()
#   _error_call()
#       _validate_input_error_call()
#   invalid_function_usage()
#
#   register_function_flags()
#       Array: _handle_args_registered_function_ids[]
#       Array: _handle_args_registered_function_short_option[]
#       Array: _handle_args_registered_function_long_option[]
#       Array: _handle_args_registered_function_values[]
#       _handle_input_register_function_flags()
#   register_help_text()
#       Array: _handle_args_registered_help_text_function_ids[]
#       Array: _handle_args_registered_help_text[]
#       _handle_input_register_help_text()
#       _validate_input_register_help_text()
#   get_help_text()
#   _handle_args()
#       _validate_input_handle_args()
#
# ##############################################################################
# ### From below here, you can call the following functions directly in the
# ### library without being within a function.
# ### * register_function_flags()
# ### * register_help_text()
# ##############################################################################
#
#   source_lib()
#   eval_cmd()
#       _validate_input_eval_cmd()
#   error()
#   warning()
#   find_path()
#       _validate_input_find_path()
#   handle_input_arrays_dynamically()
#
#   echo_color()
#   echo_warning()
#   echo_error()
#   echo_highlight()
#   echo_success()
#   command_exists()
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

get_func_def_line_num()
{
    local func_name=$1
    local script_file=$2

    local output_num

    output_num=$(grep -c "^[\s]*${func_name}()" $script_file)
    (( output_num == 1 )) || { echo '?'; return 1; }

    grep -n "^[\s]*${func_name}()" $script_file | cut -d: -f1
}

is_short_flag()
{
    local to_check="$1"

    [[ -z "$to_check" ]] && return 1

    # Check that it starts with a single hyphen, not double
    [[ "$to_check" =~ ^-[^-] ]] || return 2

    # Check that it has a single character after the hypen
    [[ "$to_check" =~ ^-[[:alpha:]]$ ]] || return 3

    return 0
}

is_long_flag()
{
    local to_check="$1"

    [[ -z "$to_check" ]] && return 1

    [[ "$to_check" =~ ^-- ]] || return 2

    # TODO: Update such that we cannot have the long flags '--_', '--__'
    #       etc.
    get_long_flag_var_name "$to_check" &>/dev/null || return 3

    return 0
}

# Outputs valid variable name if the flag is valid, replaces hyphen with underscore
get_long_flag_var_name()
{
    local long_flag="${1#--}" # Remove initial --

    grep -q '^[[:alpha:]][-[:alpha:][:digit:]]*$' <<< "$long_flag" || return 1

    # Replace hyphens with underscore
    local var_name=$(sed 's/-/_/g' <<< "$long_flag")

    valid_var_name "$var_name" || return 1

    echo "$var_name"
}

valid_var_name()
{
    grep -q '^[_[:alpha:]][_[:alpha:][:digit:]]*$' <<< "$1"
}

backtrace()
{
    local level_function_callstack=$1

    # How much to include in function call stack
    # 0 - includes backtrace()
    # 1 - includes the function calling backtrace()
    # 2 - includes 2 function above backtrace()
    local default_level_function_callstack=1

    local re='^[0-9]+$'
    [[ $level_function_callstack =~ $re ]] ||
        level_function_callstack=$default_level_function_callstack

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
    local i=$level_function_callstack
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
    i=$level_function_callstack
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

_error_call()
{
    # functions_before=1 represents the function call before this function
    local functions_before=$1
    local function_id_or_usage="$2"
    local error_info="$3"
    local start_output_message="$4"

    # local function_id="$1"
    # local error_info="$2"

    local function_usage
    function_usage=$(get_help_text "$function_id_or_usage")
    local exit_code=$?
    (( exit_code != 0 )) && function_usage="$function_id_or_usage"

    _validate_input_error_call "$@"
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
${start_output_message}

Called from:
${func_call_line_num}: ${func_call_file}
Defined at:
${func_def_line_num}: ${func_def_file}

${divider}
Backtrace:
$(backtrace $((functions_before - 1 )))

${divider}
Info:

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
_validate_input_error_call()
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

invalid_function_usage()
{
    # functions_before=1 represents the function call before this function
    local functions_before=$1
    local function_id_or_usage="$2"
    local error_info="$3"

    local func_name="${FUNCNAME[functions_before]}"

    local start_output_message
    start_output_message="!! Invalid usage of ${func_name}()"

    _error_call "$((functions_before + 1))" \
                "$function_id_or_usage" \
                "$error_info" \
                "$start_output_message"
}

# Arrays to store _handle_args() data
_handle_args_registered_function_ids=()
_handle_args_registered_function_short_option=()
_handle_args_registered_function_long_option=()
_handle_args_registered_function_values=()

# Register valid flags for a function
register_function_flags()
{
    _handle_input_register_function_flags "$1" || return

    local function_id="$1"
    shift

    if [[ -z "$function_id" ]]
    then
        define error_info <<END_OF_ERROR_INFO
Given <function_id> is empty.
END_OF_ERROR_INFO
        invalid_function_usage 1 "$function_usage" "$error_info"
        exit 1
    fi

    # Check if function id already registered
    for registered in "${_handle_args_registered_function_ids[@]}"
    do
        if [[ "$function_id" == "$registered" ]]
        then
            define error_info <<END_OF_ERROR_INFO
Given <function_id> is already registered: '$function_id'
END_OF_ERROR_INFO
            invalid_function_usage 1 "$function_usage" "$error_info"
            exit 1
        fi
    done

    local short_option=()
    local long_option=()
    local expect_value=()
    local description=()
    while (( $# > 1 ))
    do
        local input_short_flag="$1"
        local input_long_flag="$2"
        local input_expect_value="$3"
        local input_description="$4"

        if [[ -z "$input_short_flag" ]] && [[ -z "$input_long_flag"  ]]
        then
            define error_info <<END_OF_ERROR_INFO
Neither short or long flag were given for <function_id>: '$function_id'
END_OF_ERROR_INFO
            invalid_function_usage 1 "$function_usage" "$error_info"
            exit 1
        fi

        if ! is_short_flag "$input_short_flag"
        then
            local flag_exit_code=$?

            case $flag_exit_code in
                1)  ;; # Input flag empty
                2)
                    define error_info <<END_OF_ERROR_INFO
Invalid short flag format: '$input_short_flag'
Must start with a single hyphen '-'
END_OF_ERROR_INFO
                    invalid_function_usage 1 "$function_usage" "$error_info"
                    exit 1
                    ;;
                3)
                    define error_info <<END_OF_ERROR_INFO
Invalid short flag format: '$input_short_flag'
Must have exactly a single letter after the hyphen '-'
END_OF_ERROR_INFO
                    invalid_function_usage 1 "$function_usage" "$error_info"
                    exit 1
                    ;;
                *)  ;;
            esac
        fi

        # Validate long flag format, if not empty
        if ! is_long_flag "$input_long_flag"
        then
            local flag_exit_code=$?

            case $flag_exit_code in
                1)  ;; # Input flag empty
                2)
                    define error_info <<END_OF_ERROR_INFO
Invalid long flag format: '$input_long_flag'
Must start with double hyphen '--'
END_OF_ERROR_INFO
                    invalid_function_usage 1 "$function_usage" "$error_info"
                    exit 1
                    ;;
                3)
                    define error_info <<END_OF_ERROR_INFO
Invalid long flag format: '$input_long_flag'
Characters after '--' must start with a letter or underscore and can only
contain letters, numbers and underscores thereafter.
END_OF_ERROR_INFO
                    invalid_function_usage 1 "$function_usage" "$error_info"
                    exit 1
                    ;;
                *)  ;;
            esac
        fi

        # Check if 'input_expect_value' was given
        if [[ -z "$input_expect_value" ]]
        then
            define error_info << END_OF_ERROR_INFO
Missing input 'expect_value'
Must have the value of 'true' or 'false'.
END_OF_ERROR_INFO
            invalid_function_usage 1 "$function_usage" "$error_info"
            exit 1
        elif [[ "$input_expect_value" != 'true' && "$input_expect_value" != 'false' ]]
        then
            define error_info << END_OF_ERROR_INFO
Invalid 'expect_value': '$input_expect_value'
Must have the value of 'true' or 'false'.
END_OF_ERROR_INFO
            invalid_function_usage 1 "$function_usage" "$error_info"
            exit 1
        fi

        # Check if 'input_description' was given
        if [[ -z "$input_description" ]]
        then
            local flag_indicator
            if [[ -n "$input_long_flag" ]]
            then
                flag_indicator="$input_long_flag"
            else
                flag_indicator="$input_short_flag"
            fi

            define error_info << END_OF_ERROR_INFO
Missing input 'description' for flag '$flag_indicator'
END_OF_ERROR_INFO
            invalid_function_usage 1 "$function_usage" "$error_info"
            exit 1
        fi

        [[ -z "$input_short_flag" ]] && short_option+=("_") || short_option+=("$1")
        [[ -z "$input_long_flag" ]] && long_option+=("_") || long_option+=("$2")

        expect_value+=("$input_expect_value")
        description+=("$input_description")

        shift 4
    done

    ### Append to global arrays
    #
    # [*] used to save all '§' separated at the same index, to map all options
    # to the same registered function name
    local old_IFS="$IFS"
    IFS='§'
    _handle_args_registered_function_ids+=("$function_id")
    _handle_args_registered_function_short_option+=("${short_option[*]}")
    _handle_args_registered_function_long_option+=("${long_option[*]}")
    _handle_args_registered_function_values+=("${expect_value[*]}")
    _handle_args_registered_function_descriptions+=("${description[*]}")
    IFS="$old_IFS"
}

_handle_input_register_function_flags()
{
        define function_usage <<END_OF_FUNCTION_USAGE
Usage: register_function_flags <function_id> \
                               <short_flag_1> <long_flag_1> <expect_value_1> <description_1> \
                               <short_flag_2> <long_flag_2> <expect_value_2> <description_2> \
                               ...
    Registers how many function flags as you want, always in a set of 4 input
    arguments: <short_flag> <long_flag> <expect_value> <description>

    Either of <short_flag> or <long_flag> can be empty, but must then be entered
    as an empty string "".

    <function_id>:
        * Each function can have its own set of flags. The function id is used
          for identifying which flags to parse and how to parse them.
            - Function id can e.g. be the function name.
    <short_flag_#>:
        * Single dash flag.
        * E.g. '-e'
    <long_flag_#>:
        * Double dash flag
        * E.g. '--echo'
    <expect_value_#>:
        * String boolean which indicates if an associated value is expected
          after the flag.
        * 'true' = There shall be a value supplied after the flag
    <description_#>:
        * Text description of the flag
END_OF_FUNCTION_USAGE


    # Manual check as _handle_args() cannot be used, creates circular dependency
    if [[ "$1" == '-h' ]] || [[ "$1" == '--help' ]]
    then
        echo "$function_usage"
        return 1
    fi
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

# Process flags & non-optional arguments
_handle_args()
{
    local function_id="$1"
    shift
    local arguments=("$@")

    define function_usage <<'END_OF_FUNCTION_USAGE'
Usage: _handle_args <function_id> "$@"
    <function_id>:
        * Each function can have its own set of flags. The function id is used
          for identifying which flags to parse and how to parse them.
            - Function id can e.g. be the function name.
        * Should be registered through register_function_flags() before calling
          this function
END_OF_FUNCTION_USAGE

    _validate_input_handle_args
    # Output:
    # function_index

    # Look for help flag -h/--help
    for arg in "${arguments[@]}"
    do
        if [[ "$arg" == '-h' ]] || [[ "$arg" == '--help' ]]
        then
            get_help_text "$function_id"
            exit 0
        fi
    done

    local valid_short_options
    local valid_long_options
    local flags_descriptions
    local expects_value
    # Convert space separated elements into an array
    IFS='§' read -ra valid_short_options <<< "${_handle_args_registered_function_short_option[function_index]}"
    IFS='§' read -ra valid_long_options <<< "${_handle_args_registered_function_long_option[function_index]}"
    IFS='§' read -ra flags_descriptions <<< "${_handle_args_registered_function_descriptions[function_index]}"
    IFS='§' read -ra expects_value <<< "${_handle_args_registered_function_values[function_index]}"

    local registered_help_text="${_handle_args_registered_help_text[function_help_text_index]}"

    # Declare and initialize output variables
    # <long/short option>_flag = 'false'
    # <long/short option>_flag_value = ''
    for i in "${!valid_short_options[@]}"
    do
        local derived_flag_name=""

        # Find out variable naming prefix
        # Prefer the long option name if it exists
        if [[ "${valid_long_options[$i]}" != "_" ]]
        then
            derived_flag_name=$(get_long_flag_var_name "${valid_long_options[$i]}")
            derived_flag_name="${derived_flag_name}_flag"
        else
            derived_flag_name="${valid_short_options[$i]#-}_flag"
        fi

        # Initialization
        declare -g "$derived_flag_name"='false'
        if [[ "${expects_value[$i]}" == "true" ]]
        then
            declare -g "${derived_flag_name}_value"=''
        fi
    done

    non_flagged_args=()
    for (( i=0; i<${#arguments[@]}; i++ ))
    do
        is_long_flag "${arguments[i]}"; is_long_flag_exit_code=$?

        if (( $is_long_flag_exit_code == 3 ))
        then
            # TODO: Update such that '-' can be used in the flag name
            define error_info << END_OF_ERROR_INFO
Given long flag have invalid format, cannot create variable name from it: '${arguments[i]}'
END_OF_ERROR_INFO

            define function_usage_register_function_flags << END_OF_FUNCTION_USAGE
Registered flags through register_function_flags() must follow the valid_var_name() validation.
END_OF_FUNCTION_USAGE

            # TODO: Replace with more general error
            invalid_function_usage 0 "$function_usage_register_function_flags" "$error_info"
            exit 1
        fi

        if ! is_short_flag "${arguments[i]}" && (( is_long_flag_exit_code != 0))
        then
            # Not a flag
            non_flagged_args+=("${arguments[i]}")
            continue
        fi

        local was_option_handled='false'

        for j in "${!valid_short_options[@]}"
        do
            local derived_flag_name=""
            if [[ "${arguments[i]}" == "${valid_long_options[j]}" ]] || \
               [[ "${arguments[i]}" == "${valid_short_options[j]}" ]]
            then

                # Find out variable naming prefix
                # Prefer the long option name if it exists
                if [[ "${valid_long_options[j]}" != "_" ]]
                then
                    derived_flag_name=$(get_long_flag_var_name "${valid_long_options[j]}")
                    derived_flag_name="${derived_flag_name}_flag"
                else
                    derived_flag_name="${valid_short_options[j]#-}_flag"
                fi

                # Indicate that flag was given
                declare -g "$derived_flag_name"='true'

                if [[ "${expects_value[j]}" == 'true' ]]
                then
                    ((i++))

                    local first_character_hyphen='false'
                    [[ "${arguments[i]:0:1}" == "-" ]] && first_character_hyphen='true'

                    if [[ -z "${arguments[i]}" ]] || [[ "$first_character_hyphen" == 'true' ]]
                    then
                        define error_info <<END_OF_ERROR_INFO
Option ${valid_short_options[j]} and ${valid_long_options[j]} expects a value supplied after it."
END_OF_ERROR_INFO
                        invalid_function_usage 2 "$function_usage" "$error_info"
                        exit 1
                    fi

                    # Store given value after flag
                    declare -g "${derived_flag_name}_value"="${arguments[i]}"
                fi

                was_option_handled='true'
                break
            fi
        done

        if [[ "$was_option_handled" != 'true' ]]
        then
            define error_info <<END_OF_ERROR_INFO
Given flag '${arguments[i]}' is not registered for function id: '$function_id'

$(register_function_flags --help)
END_OF_ERROR_INFO
            invalid_function_usage 3 "$function_usage" "$error_info"
            exit 1
        fi
    done
}

_validate_input_handle_args()
{
    if [[ -z "$function_id" ]]
    then
        define error_info <<'END_OF_ERROR_INFO'
Given <function_id> is empty.
END_OF_ERROR_INFO
        invalid_function_usage 3 "$function_usage" "$error_info"
        exit 1
    fi

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

    if [[ "$function_registered" != 'true' ]]
    then
        define error_info <<END_OF_ERROR_INFO
Given <function_id> is not registered through register_function_flags() before
calling _handle_args(). <function_id>: '$function_id'

$(register_function_flags --help)
END_OF_ERROR_INFO
        invalid_function_usage 3 "$function_usage" "$error_info"
        exit 1
    fi

    ###
    # Check that <function_id> is registered through register_help_text()
    local function_help_text_registered='false'
    for i in "${!_handle_args_registered_help_text_function_ids[@]}"
    do
        if [[ "${_handle_args_registered_help_text_function_ids[$i]}" == "$function_id" ]]
        then
            function_help_text_registered='true'
            function_help_text_index=$i
            break
        fi
    done

    if [[ "$function_help_text_registered" != 'true' ]]
    then
        define error_info <<END_OF_ERROR_INFO
Given <function_id> is not registered through register_help_text() before
calling _handle_args(). <function_id>: '$function_id'

$(register_help_text --help)
END_OF_ERROR_INFO
        invalid_function_usage 3 "$function_usage" "$error_info"
        exit 1
    fi
}

################################################################################
################################################################################
##### From below here, you can call register_function_flags()
##### This is because of circular dependencies if called before
################################################################################
################################################################################

# For previous _error_call()
#
# Very important to call both functions for '_error_call' to avoid circular call:
# - register_function_flags()
# - register_help_text() 
register_function_flags '_error_call' \
                        '' '--no-defined-at' 'false' \
                        "Do not output where the function called function is defined at." \
                        '' '--no-backtrace' 'false' \
                        "Do not output a backtrace of function calls." \
                        '' '--no-extra-info' 'false' \
                        "Do not output extra info." \
                        '' '--no-help-text' 'false' \
                        "Do not output a function help text" \
                        '' '--manual-help-text' 'true' \
                        "Instead of using '<function_id> to get the help text, give the help text manually."
                        

# For previous _error_call()
#
# Very important to call both functions for '_error_call' to avoid circular call:
# - register_function_flags()
# - register_help_text() 
register_help_text '_error_call' \
"_error_call <functions_before> <function_id> <extra_info> <start_output_message>

Arguments:
    <functions_before>:
        Used for the output 'Defined at' & 'Backtrace' sections.
        Which function which to mark with the error.
        - '0': This function: _error_call()
        - '1': 1 function before this. Which calls _error_call()
        - '2': 2 functions before this
    <function_id>:
        Used for the output 'Help text' section.
        Function ID used to register the function help text & flags:
        - register_help_test()
        - register_function_flags()
    <extra_info>:
        Single-/Multi-line with extra info.
        - Example:
            \"Invalid input <arg_two>: '\$arg_two'\"
    <start_output_message>:
        First line of the error message, indicating what kind of error.
        - Example:
            \"Error in \${func_name}()\""


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
        echo_error "$error_info"
        echo_error "Could not source library even though the file exists: '$lib'"
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

error()
{
    # functions_before=1 represents the function call before this function
    local functions_before=$1
    local function_id_or_usage="$2"
    local error_info="$3"

    local func_name="${FUNCNAME[functions_before]}"

    local start_output_message
    start_output_message="!! Error in ${func_name}()"

    _error_call "$((functions_before + 1))" \
                "$function_id_or_usage" \
                "$error_info" \
                "$start_output_message"
}

warning()
{
    # functions_before=1 represents the function call before this function
    local functions_before=$1
    local function_id_or_usage="$2"
    local error_info="$3"

    local func_name="${FUNCNAME[functions_before]}"

    local start_output_message
    start_output_message="!! Warning in ${func_name}()"

    _error_call "$((functions_before + 1))" \
                "$function_id_or_usage" \
                "$error_info" \
                "$start_output_message"
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

# Used for handling arrays as function parameters
# Creates dynamic arrays from the input
# 1: Dynamic array name prefix e.g. 'input_arr'
#    Creates dynamic arrays 'input_arr1', 'input_arr2', ...
# 2: Length of array e.g. "${#arr[@]}"
# 3: Array content e.g. "${arr[@]}"
# 4: Length of the next array
# 5: Content of the next array
# 6: ...
handle_input_arrays_dynamically()
{
    local dynamic_array_prefix="$1"; shift
    local array_suffix=1

    local is_number_regex='^[0-9]+$'

    while (( $# ))
    do
        local num_array_elements=$1; shift

        if ! [[ "$num_array_elements" =~ $is_number_regex ]]
        then
            echo "Given number of array elements is not a number: $num_array_elements"
            exit 1
        fi

        eval "$dynamic_array_prefix$array_suffix=()";
        while (( num_array_elements-- > 0 ))
        do

            if ((num_array_elements == 0)) && ! [[ "${1+nonexistent}" ]]
            then
                # Last element is not set
                echo "Given array contains less elements than the explicit array size given."
                exit 1
            fi
            eval "$dynamic_array_prefix$array_suffix+=(\"\$1\")"; shift
        done
        ((array_suffix++))
    done
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
    # Flush stderr by line-buffering stdout of echo and redirecting it to stderr
    stdbuf -oL printf "" >&2
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
