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
# Used internally in library
readonly ARRAY_SEPARATOR='§'

# Arrays to store _handle_args() data
_handle_args_registered_function_ids=()
_handle_args_registered_function_short_option=()
_handle_args_registered_function_long_option=()
_handle_args_registered_function_values=()
_handle_args_registered_function_descriptions=()
_handle_args_registered_help_text_function_ids=()
_handle_args_registered_help_text=()
###

###
# List of global definitions - Functions, variables, arrays
#
#   Color variables
#
#   Variable: ARRAY_SEPARATOR
#   Array: _handle_args_registered_function_ids[]
#   Array: _handle_args_registered_function_short_option[]
#   Array: _handle_args_registered_function_long_option[]
#   Array: _handle_args_registered_function_values[]
#   Array: _handle_args_registered_help_text_function_ids[]
#   Array: _handle_args_registered_help_text[]
#
#   define()
#   
#   Variable: _function_index_dumb_add
#   _dumb_add_function_flags_and_help_text()
#       _add_separator_to_arrays_handle_args()
#
#   === Dumb registering function flags & help texts ===
#
#   get_func_def_line_num()
#   is_short_flag()
#   is_long_flag()
#   get_long_flag_var_name()
#   valid_var_name()
#
#   backtrace()
#   _error_call()
#       _handle_args_error_call()
#       _get_func_info()
#       _create_wrapper_divider()
#       _create_start_message()
#       _append_defined_at_output_message()
#       _append_backtrace_output_message()
#       _append_extra_info_output_message()
#       _append_help_text_output_message()
#       _append_end_wrapper_output_message()
#       
#   invalid_function_usage()
#
#   register_function_flags()
#       _handle_input_register_function_flags()
#   register_help_text()
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
    check_for_help_flag 'define' "$@"

    IFS= read -r -d '' "$1" || true
    # Remove the trailing newline
    eval "$1=\${$1%$'\n'}"
}

_function_index_dumb_add=0
# Used for core functions in this library to avoid circular dependencies
#
# Registers flags and help text for a function, without doing much checking of
# correct usage of the function. Is replaced by register_function_flags() and
# register_help_text() later on, which utilizes the same global arrays.
_dumb_add_function_flags_and_help_text()
{
    local function_index="$1"
    local function_id="$2"
    local help_text="$3"
    shift 3

    local re='^[0-9]+$'
    if ! [[ $function_index =~ $re ]]
    then
        echo "Given function index to _tmp_add_function_flags() is not a number: '$function_index'" >&2
        exit 1
    fi

    _add_separator_to_arrays_handle_args()
    {
        _handle_args_registered_function_short_option[$function_index]+="$ARRAY_SEPARATOR"
        _handle_args_registered_function_long_option[$function_index]+="$ARRAY_SEPARATOR"
        _handle_args_registered_function_values[$function_index]+="$ARRAY_SEPARATOR"
        _handle_args_registered_function_descriptions[$function_index]+="$ARRAY_SEPARATOR"
    }

    _handle_args_registered_function_ids[$function_index]="$function_id"
    _handle_args_registered_help_text_function_ids[$function_index]="$function_id"

    _handle_args_registered_help_text[$function_index]="$help_text"

    local first_iter='true'

    while (( $# > 1 ))
    do
        local input_short_flag="$1"
        local input_long_flag="$2"
        local input_expect_value="$3"
        local input_description="$4"
        shift 4

        [[ -z "$input_short_flag" ]] && input_short_flag='_'

        if [[ "$first_iter" == 'true' ]]
        then
            first_iter='false'
        else
            _add_separator_to_arrays_handle_args
        fi

        _handle_args_registered_function_short_option[$function_index]+="$input_short_flag"
        _handle_args_registered_function_long_option[$function_index]+="$input_long_flag"
        _handle_args_registered_function_values[$function_index]+="$input_expect_value"
        _handle_args_registered_function_descriptions[$function_index]+="$input_description"
    done
}

check_for_help_flag()
{
    local function_id="$1"
    shift
    local arguments=("$@")

    # Check help flag for this function
    if [[ "$function_id" == '-h' || "$function_id" == '--help' ]]
    then
        get_help_text 'check_for_help_flag'
        exit 0
    fi

    # Look for flag --strict-check-only-help-flag
    local strict_check='false'
    for arg in "${arguments[@]}"
    do
        if [[ "$arg" == '--strict-check-only-help-flag' ]]
        then
            strict_check='true'
        fi
    done

    local found_help_flag='false'
    local found_other='false'
    # Look for help flag -h/--help
    for arg in "${arguments[@]}"
    do
        if [[ "$arg" == '-h' ]] || [[ "$arg" == '--help' ]]
        then
            found_help_flag='true'
        else
            found_other='true'
        fi
    done

    [[ "$found_help_flag" != 'true' ]] && return 0

    if [[ "$strict_check" == 'true' && "$found_other" == 'true' ]] 
    then
        return 0
    fi

    get_help_text "$function_id"
    exit 0
}

get_help_text()
{
    check_for_help_flag 'get_help_text' "$@"

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
    # Output first part of help text
    echo "${registered_help_text}"

    get_flags_info "$function_id"

    return 0
}

get_flags_info()
{
    check_for_help_flag 'get_flags_info' "$@"

    local function_id="$1"

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

    [[ "$function_registered" != 'true' ]] && return 0

    ###
    # Get flags and corresponding descriptions for <function_id>
    local valid_short_options
    local valid_long_options
    local flags_descriptions
    # Convert space separated elements into an array
    IFS="${ARRAY_SEPARATOR}" read -ra valid_short_options <<< "${_handle_args_registered_function_short_option[function_index]}"
    IFS="${ARRAY_SEPARATOR}" read -ra valid_long_options <<< "${_handle_args_registered_function_long_option[function_index]}"
    IFS="${ARRAY_SEPARATOR}" read -ra flags_descriptions <<< "${_handle_args_registered_function_descriptions[function_index]}"

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

    (( ${#array_flag_description_line[@]} == 0 )) && return 0

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

################################################################################
################################################################################
##### Dumb add function flags & help texts for the most important functions.
##### Use function with bare minimum validation.
##### This is to avoid circular dependencies.
##### This should be done with functions down to comment marking:
##### 'ALLOW FUNCTION CALLS register_function_flags() & register_help_text()'
################################################################################
################################################################################

###
# Dumb add function flags and help text for check_for_help_flag()
define help_text <<'END_OF_HELP_TEXT'
check_for_help_flag <function_id> "$@"

Used to check for the -h/--help flags in the function arguments "$@". If found,
it outputs the help text using the <function_id> registered help text.

Arguments:
    <function_id>:
        ID of function which to output the help text for if a help flag is given
        in the arguments "$@"

Flags:
    --strict-check-only-help-flag    Used to show help text if there is only a help flag given as argument, and nothing else.
END_OF_HELP_TEXT

_dumb_add_function_flags_and_help_text "$((_function_index_dumb_add++))" \
    'check_for_help_flag' \
    "$help_text"
# check_for_help_flag() help text
###

###
# Dumb add function flags and help text for define()
define help_text <<END_OF_HELP_TEXT
Easily creates variable with multiline text. With or without evaluation.
Utilizes heredoc as seen in the examples below.

For no evaluation, having the exact text stored in the variable:

    define <varname> <<'END_OF_TEXT'
<text>
<text>
END_OF_TEXT

For evaluation, of e.g. variables and backslash:

    define <varname> <<END_OF_TEXT
<text>
<text>
END_OF_TEXT
END_OF_HELP_TEXT

_dumb_add_function_flags_and_help_text "$((_function_index_dumb_add++))" \
    'define' \
    "$help_text"
# define() help text
###

###
# Dumb add function flags and help text for get_func_def_line_num()
define help_text <<END_OF_HELP_TEXT
get_func_def_line_num <func_name> <script_file>

Finds defined function <func_name> in <script_file> and outputs its definition
line number if exactly 1 instance is found. It does only look for functions
defined in the form:

    my_func()

and thereby not

    function myfunc

Arguments:
    <func_name>:
        The name of the function to look for
    <script_file>:
        The file to look for the function in

Return value:
    0 if successful
    Non-zero if failure
END_OF_HELP_TEXT

_dumb_add_function_flags_and_help_text "$((_function_index_dumb_add++))" \
    'get_func_def_line_num' \
    "$help_text"
# get_func_def_line_num() help text
###

###
# Dumb add function flags and help text for is_short_flag()
define help_text <<END_OF_HELP_TEXT
is_short_flag <to_check>

Checks whether given <to_check> is a short flag, that is with a single hyphen
and that there is a single character after the hyphen.

Arguments:
    <to_check>: The text to check if it is a short flag

Return value:
    0 if it is a short flag
    1 if empty
    2 if double hyphen
    3 if not single character
END_OF_HELP_TEXT

_dumb_add_function_flags_and_help_text "$((_function_index_dumb_add++))" \
    'is_short_flag' \
    "$help_text"
# is_short_flag() help text
###

###
# Dumb add function flags and help text for is_long_flag()
define help_text <<END_OF_HELP_TEXT
is_long_flag <to_check>

Checks whether given <to_check> is a long flag, that is with a double hyphen
and that the following text can be converted to a variable.

Arguments:
    <to_check>: The text to check if it is a long flag

Return value:
    0 if it is a long flag
    1 if empty
    2 if not double hyphen
    3 if not possible to create valid variable name from the following text
END_OF_HELP_TEXT

_dumb_add_function_flags_and_help_text "$((_function_index_dumb_add++))" \
    'is_long_flag' \
    "$help_text"
# is_long_flag() help text
###

###
# Dumb add function flags and help text for get_long_flag_var_name()
define help_text <<END_OF_HELP_TEXT
get_long_flag_var_name <long_flag>

Checks whether <long_flag> can be converted to a variable name. Replaces hyphens
with underscores. Echos the variable name.

Arguments:
    <long_flag>: The long flag, including double hyphen, to convert to
                 variable name

Return value:
    0 if successful in converting to variable name
    1 if not possible to convert to variable name
END_OF_HELP_TEXT

_dumb_add_function_flags_and_help_text "$((_function_index_dumb_add++))" \
    'get_long_flag_var_name' \
    "$help_text"
# get_long_flag_var_name() help text
###

###
# Dumb add function flags and help text for valid_var_name()
define help_text <<END_OF_HELP_TEXT
valid_var_name <var_name>

Checks whether <var_name> is a valid variable name.

Arguments:
    <valid_var_name>: The text to check if valid variable

Return value:
    0 if valid
    Non-zero if invalid
END_OF_HELP_TEXT

_dumb_add_function_flags_and_help_text "$((_function_index_dumb_add++))" \
    'valid_var_name' \
    "$help_text"
# valid_var_name() help text
###

###
# Dumb add function flags and help text for backtrace()
define help_text <<END_OF_HELP_TEXT
backtrace [level_function_callstack]

Prints the function callstack at the current state.

Arguments:
    [level_function_callstack]: Optional.
        How far back in the function callstack to show.
        0 - includes backtrace() call
        1 - includes the function calling backtrace()
        2 - includes 2 function above backtrace()
        etc.

Return value:
    Always 0
END_OF_HELP_TEXT

_dumb_add_function_flags_and_help_text "$((_function_index_dumb_add++))" \
    'backtrace' \
    "$help_text"
# backtrace() help text
###

###
# Dumb add function flags and help text for _error_call()
define help_text <<'END_OF_HELP_TEXT'
_error_call <functions_before>
            <function_id>
            <extra_info>
            <start_output_message>

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
            "Invalid input <arg_two>: '$arg_two'"
    <start_output_message>:
        First line of the error message, indicating what kind of error.
        - Example:
            "Error in ${func_name}()"
END_OF_HELP_TEXT

_dumb_add_function_flags_and_help_text "$((_function_index_dumb_add++))" \
    '_error_call' \
    "$help_text" \
    '' '--backtrace-level' 'true' \
    "<num> - How deep to backtrace function calls. <num> function calls before _error_call()" \
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
# _error_call() help text
###

###
# Dumb add function flags and help text for invalid_function_usage()
define help_text <<END_OF_HELP_TEXT
invalid_function_usage <functions_before>
                       <function_id>
                       <extra_info>
                       <start_output_message>

All the rest of the arguments e.g. flags will be passed to _error_call(), see
the help text of _error_call() for more information.

Arguments:
    <functions_before>:
        Used for the output 'Defined at' & 'Backtrace' sections.
        Which function which to mark with the error.
        - '0': The function calling invalid_function_usage()
        - '1': 1 function before that
        - '2': 2 functions before that
        - '#': etc.
    <function_id>:
        Used for the output 'Help text' section.
        Function ID used to register the function help text & flags:
        - register_hel main.sh sources script_1.invalid_function_p_test()
        - register_function_flags()
    <extra_info>:
        Single-/Multi-line with extra info.
        - Example:
            "Invalid input <arg_two>: '\$arg_two'"
    <start_output_message>:
        First line of the error message, indicating what kind of error.

        By defining the variable PLACEHOLDER_FUNC_NAME inside the function
        calling _error_call() and including "\${PLACEHOLDER_FUNC_NAME}" in the
        <start_message>, it will be replaced with the function name based upon
        <functions_before>.

        - Example:
            local PLACEHOLDER_FUNC_NAME='<__PLACEHOLDER_FUNC_NAME__>'
            start_output_message="Error in \${PLACEHOLDER_FUNC_NAME}"

Help text for _error_call():

$(get_help_text '_error_call')
END_OF_HELP_TEXT

_dumb_add_function_flags_and_help_text "$((_function_index_dumb_add++))" \
    'invalid_function_usage' \
    "$help_text"
# invalid_function_usage() help text
###

###
# Dumb add function flags and help text for register_function_flags()
define help_text <<END_OF_HELP_TEXT
register_function_flags <function_id>
                        <short_flag_1> <long_flag_1> <expect_value_1> <description_1>
                        <short_flag_2> <long_flag_2> <expect_value_2> <description_2>
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
END_OF_HELP_TEXT

_dumb_add_function_flags_and_help_text "$((_function_index_dumb_add++))" \
    'register_function_flags' \
    "$help_text"
###

###
# Dumb add function flags and help text for register_help_text()
define help_text <<END_OF_HELP_TEXT
register_help_text <function_id> <help_text>

Arguments:
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
END_OF_HELP_TEXT

_dumb_add_function_flags_and_help_text $((_function_index_dumb_add++)) \
    'register_help_text' \
    "$help_text"
# register_help_text() help text
###

###
# Dumb add function flags and help text for get_help_text()
define help_text <<END_OF_HELP_TEXT
get_help_text <function_id>

Outputs the help text of the requested <function_id> which have been registered
using register_help_text().

Arguments:
    <function_id>:
        The function id to get the help text from
END_OF_HELP_TEXT

_dumb_add_function_flags_and_help_text $((_function_index_dumb_add++)) \
    'get_help_text' \
    "$help_text"
# get_help_text() help text
###

###
# Dumb add function flags and help text for get_flags_info()
define help_text <<END_OF_HELP_TEXT
get_flags_info <function_id>

Outputs the flags information of the requested <function_id> which have been
registered using register_function_flags().

Arguments:
    <function_id>:
        The function id to get the flags information from
END_OF_HELP_TEXT

_dumb_add_function_flags_and_help_text $((_function_index_dumb_add++)) \
    'get_flags_info' \
    "$help_text"
# get_help_text() help text
###

###
# Dumb add function flags and help text for get_help_text()
define help_text <<'END_OF_HELP_TEXT'
_handle_args <function_id> "$@"

Used for handling input arguments. This includes flags registered through
register_function_flags().

Arguments:
    <function_id>:
        * Each function can have its own set of flags. The function id is used
          for identifying which flags to parse and how to parse them.
            - Function id can e.g. be the function name.
        * Should be registered through register_function_flags() before calling
          this function
Flags:
    --allow-non-registered-flags    Will allow pass-through and not exit if unregistered flag is used
END_OF_HELP_TEXT

_dumb_add_function_flags_and_help_text $((_function_index_dumb_add++)) \
    '_handle_args' \
    "$help_text"
# _handle_args() help text
###

################################################################################
################################################################################
##### End of dumb adding function flags & help texts.
################################################################################
################################################################################

get_func_def_line_num()
{
    check_for_help_flag 'get_func_def_line_num' "$@"

    local func_name=$1
    local script_file=$2

    local output_num

    output_num=$(grep -c "^[\s]*${func_name}()" $script_file)
    (( output_num == 1 )) || { echo '?'; return 1; }

    grep -n "^[\s]*${func_name}()" $script_file | cut -d: -f1
}

is_short_flag()
{
    check_for_help_flag 'is_short_flag' "$@"

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
    check_for_help_flag 'is_long_flag' "$@"

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
    check_for_help_flag 'get_long_flag_var_name' "$@"

    local long_flag="${1#--}" # Remove initial --

    grep -q '^[[:alpha:]][-[:alpha:][:digit:]]*$' <<< "$long_flag" || return 1

    # Replace hyphens with underscore
    local var_name=$(sed 's/-/_/g' <<< "$long_flag")

    valid_var_name "$var_name" || return 1

    echo "$var_name"
}

valid_var_name()
{
    check_for_help_flag 'valid_var_name' "$@"

    grep -q '^[_[:alpha:]][_[:alpha:][:digit:]]*$' <<< "$1"
}

backtrace()
{
    check_for_help_flag 'backtrace' "$@"

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
    local functions_before
    local function_id
    local extra_info
    local start_message

    # Flags stored local. Cannot make '<var>_flag' local as it will be unset
    # before stored as global.
    local backtrace_level_given
    local backtrace_level
    local no_defined_at
    local no_backtrace
    local no_extra_info
    local no_help_text
    local manual_help_text

    if ! _handle_args_error_call "$@"
    then
        # Invalid usage of _error_call(), redefine error according to this.
        no_defined_at='false'
        no_backtrace='false'
        no_extra_info='false'
        no_help_text='false'

        functions_before=0
        help_text=$(get_help_text '_error_call')

        local func_name
        local func_def_file func_def_line_num
        local func_call_file func_call_line_num
        _get_func_info "$functions_before"

        start_message="!! Invalid usage of ${func_name}()"
    else
        local func_name
        local func_def_file func_def_line_num
        local func_call_file func_call_line_num
        _get_func_info "$functions_before"

        # Create PLACEHOLDER_FUNC_NAME in function calling this function.
        # Use it for replacing function name inside this function
        [[ -n "$PLACEHOLDER_FUNC_NAME" ]] &&
            start_message="${start_message//${PLACEHOLDER_FUNC_NAME}/${func_name}()}"
        
        start_message="!! ${start_message}"
    fi

    local wrapper
    local divider
    _create_wrapper_divider
    local potentially_divider=""

    local output_message

    _create_start_message

    [[ "$no_defined_at" != 'true' ]] &&
        _append_defined_at_output_message

    [[ "$no_backtrace" != 'true' ]] &&
        _append_backtrace_output_message

    [[ "$no_extra_info" != 'true' ]] &&
        _append_extra_info_output_message

    [[ "$no_help_text" != 'true' ]] &&
        _append_help_text_output_message

    _append_end_wrapper_output_message

    echo "$output_message" >&2
    [[ "$invalid_usage_of_this_func" == 'true' ]] && exit 1
}

_handle_args_error_call()
{
    _handle_args '_error_call' "$@"

    #####
    # Non-flagged arguments
    functions_before="${non_flagged_args[0]}"
    function_id="${non_flagged_args[1]}"
    extra_info="${non_flagged_args[2]}"
    start_message="${non_flagged_args[3]}"
    #####

    #####
    # Flags
    if [[ "$backtrace_level_flag" == 'true' ]]
    then
        backtrace_level_given='true'
        backtrace_level="$backtrace_level_flag_value"
    fi

    [[ "$no_defined_at_flag" == 'true' ]] &&
        no_defined_at='true'

    [[ "$no_backtrace_flag" == 'true' ]] &&
        no_backtrace='true'

    [[ "$no_extra_info_flag" == 'true' ]] &&
        no_extra_info='true'

    [[ "$no_help_text_flag" == 'true' ]] &&
        no_help_text='true'

    if [[ "$manual_help_text_flag" == 'true' ]]
    then
        manual_help_text='true'
        help_text="$manual_help_text_flag_value"
    fi
    #####

    #####
    # Validation

    # Output requirements - Defined at
    if [[ "$no_defined_at" != 'true' ]]
    then
        local re='^[0-9]+$'
        if ! [[ $functions_before =~ $re ]]
        then
            invalid_usage_of_this_func='true'

            define extra_info <<END_OF_EXTRA_INFO
Given input <functions_before> is not a number: '$functions_before'
END_OF_EXTRA_INFO
            return 1
        fi
    fi

    # Output requirements - Backtrace
    if [[ "$no_backtrace" != 'true' ]]
    then
        local number_re='^[0-9]+$'

        if [[ "$backtrace_level_given" == 'true' ]]
        then
            if ! [[ $backtrace_level =~ $number_re ]]
            then
                define extra_info <<END_OF_EXTRA_INFO
The flag --backtrace-level expects a number after it: '$backtrace_level'
END_OF_EXTRA_INFO
                return 1
            fi
        elif ! [[ $functions_before =~ $number_re ]]
        then
            invalid_usage_of_this_func='true'

            define extra_info <<END_OF_EXTRA_INFO
Given input <functions_before> is not a number: '$functions_before'
END_OF_EXTRA_INFO
            return 1
        else
            backtrace_level="$functions_before"
        fi
    fi

    # Output requirements - Extra info
    if [[ "$no_extra_info" != 'true' ]]
    then
        if [[ -z "$extra_info" ]]
        then
            invalid_usage_of_this_func='true'

            define extra_info <<END_OF_EXTRA_INFO
Given input <extra_info> missing.
END_OF_EXTRA_INFO
            return 1
        fi
    fi

    # Output requirements - Help text
    if [[ "$no_help_text" != 'true' ]]
    then
        if [[ "$manual_help_text" != 'true' ]]
        then
            # If no manual help text, <function_id> is expected
            if [[ -z "$function_id" ]]
            then
                invalid_usage_of_this_func='true'

                define extra_info <<END_OF_EXTRA_INFO
Given input <function_id> missing.
END_OF_EXTRA_INFO
                return 1
            fi

            help_text=$(get_help_text "$function_id")

            local exit_code=$?
            if (( exit_code != 0 ))
            then
                invalid_usage_of_this_func='true'
                define extra_info <<END_OF_EXTRA_INFO
No help text registered through 'register_help_text' for given <function_id>: '$function_id'
END_OF_EXTRA_INFO
                return 1
            fi
        fi
    fi

    # Output requirements - Start of output message
    if [[ -z "$start_message" ]]
    then
        invalid_usage_of_this_func='true'
        define extra_info <<END_OF_EXTRA_INFO
Given input <start_message> missing.
END_OF_EXTRA_INFO
        return 1
    fi
    #####
}

_get_func_info()
{
    local functions_before="$1"

    ((functions_before = functions_before + 2))

    func_name="${FUNCNAME[functions_before]}"
    func_def_file="${BASH_SOURCE[functions_before]}"
    func_def_line_num="$(get_func_def_line_num $func_name $func_def_file)"
    func_call_file="${BASH_SOURCE[functions_before + 1]}"
    func_call_line_num="${BASH_LINENO[functions_before]}"
}

_create_wrapper_divider()
{
    # Update COLUMNS regardless if shopt checkwinsize is enabled
    if [[ -c /dev/tty ]]
    then
        # Pass /dev/tty to the command as if running as background process, the shell
        # is not attached to a terminal
        IFS=' ' read LINES COLUMNS < <(stty size </dev/tty)
    else
        COLUMNS=80
    fi

    wrapper="$(printf "%.s#" $(seq $COLUMNS))"
    divider="$(printf "%.s-" $(seq $COLUMNS))"
}

_create_start_message()
{
    define output_message <<END_OF_VARIABLE_WITH_EVAL

${wrapper}
${start_message}
END_OF_VARIABLE_WITH_EVAL
}

_append_defined_at_output_message()
{
    define output_message <<END_OF_VARIABLE_WITH_EVAL
${output_message}
${potentially_divider}
Function:
    ${func_name}()
Called from:
    ${func_call_line_num}: ${func_call_file}
Defined at:
    ${func_def_line_num}: ${func_def_file}

END_OF_VARIABLE_WITH_EVAL
    potentially_divider="$divider"
}

_append_backtrace_output_message()
{
    define output_message <<END_OF_VARIABLE_WITH_EVAL
${output_message}
${potentially_divider}
Backtrace:
$(backtrace $((backtrace_level + 2)))

END_OF_VARIABLE_WITH_EVAL
    potentially_divider="$divider"
}

_append_extra_info_output_message()
{
    define output_message <<END_OF_VARIABLE_WITH_EVAL
${output_message}
${potentially_divider}
Extra info:

${extra_info}

END_OF_VARIABLE_WITH_EVAL
    potentially_divider="$divider"
}

_append_help_text_output_message()
{
    define output_message <<END_OF_VARIABLE_WITH_EVAL
${output_message}
${potentially_divider}
Help text:

${help_text}

END_OF_VARIABLE_WITH_EVAL
    potentially_divider="$divider"
}

_append_end_wrapper_output_message()
{
    define output_message <<END_OF_VARIABLE_WITH_EVAL
${output_message}
${wrapper}
END_OF_VARIABLE_WITH_EVAL
}

invalid_function_usage()
{
    local functions_before
    local function_id
    local extra_info

    _handle_args_invalid_function_usage "$@"
    shift 3

    declare -r PLACEHOLDER_FUNC_NAME='<__PLACEHOLDER_FUNC_NAME__>'
    local start_message="Invalid usage of ${PLACEHOLDER_FUNC_NAME}"

    # Pass first 3 arguments, then 'start_message' and
    # thereafter all the rest. All the rest can be optional flags etc.
    _error_call "$((functions_before + 1))" \
                "$function_id" \
                "$extra_info" \
                "$start_message" \
                --backtrace-level 1 \
                "$@"
}

_handle_args_invalid_function_usage()
{
    _handle_args 'invalid_function_usage' --allow-non-registered-flags "$@"

    functions_before="${non_flagged_args[0]}"
    function_id="${non_flagged_args[1]}"
    extra_info="${non_flagged_args[2]}"

    # Validate to be number as we will manipulate it. Thereby a need to check it
    # before calling _error_call() instead of relying on its check
    _validate_functions_before_variable 'invalid_function_usage' "$functions_before"
}

_validate_functions_before_variable()
{
    local function_id_calling_this_func="$1"
    local functions_before="$2"

    local number_re='^[0-9]+$'
    if ! [[ $functions_before =~ $number_re ]]
    then
        local error_info="Given <functions_before> is not a number: '$functions_before'"
        local functions_before=2
        declare -r PLACEHOLDER_FUNC_NAME='<__PLACEHOLDER_FUNC_NAME__>'
        local start_output_message="Invalid usage of ${PLACEHOLDER_FUNC_NAME}"

        _error_call "$functions_before" \
                    "$function_id_calling_this_func" \
                    "$error_info" \
                    "$start_output_message" \
                    --backtrace-level 0
        exit 1
    fi
}

# Register valid flags for a function
#
# The function will do the following if used correctly:
# 1. Add function id to
#       _handle_args_registered_function_ids[]
# 2. Add short flag to
#       _handle_args_registered_function_short_option[]
#    or an underscore '_' if none
# 3. Add long flag to
#       _handle_args_registered_function_long_option[]
#    or an underscore '_' if none
# 4. Add if expecting value after flag, 'true' or 'false'  to
#       _handle_args_registered_function_values[]
#
register_function_flags()
{
    local function_id
    _handle_input_register_function_flags "$@"
    shift

    if [[ -z "$function_id" ]]
    then
        define error_info <<END_OF_ERROR_INFO
Given <function_id> is empty.
END_OF_ERROR_INFO
        invalid_function_usage 0 'register_function_flags' "$error_info"
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
            invalid_function_usage 0 'register_function_flags' "$error_info"
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
            invalid_function_usage 0 'register_function_flags' "$error_info"
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
                    invalid_function_usage 0 'register_function_flags' "$error_info"
                    exit 1
                    ;;
                3)
                    define error_info <<END_OF_ERROR_INFO
Invalid short flag format: '$input_short_flag'
Must have exactly a single letter after the hyphen '-'
END_OF_ERROR_INFO
                    invalid_function_usage 0 'register_function_flags' "$error_info"
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
                    invalid_function_usage 0 'register_function_flags' "$error_info"
                    exit 1
                    ;;
                3)
                    define error_info <<END_OF_ERROR_INFO
Invalid long flag format: '$input_long_flag'
Characters after '--' must start with a letter or underscore and can only
contain letters, numbers and underscores thereafter.
END_OF_ERROR_INFO
                    invalid_function_usage 0 'register_function_flags' "$error_info"
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
            invalid_function_usage 0 'register_function_flags' "$error_info"
            exit 1
        elif [[ "$input_expect_value" != 'true' && "$input_expect_value" != 'false' ]]
        then
            define error_info << END_OF_ERROR_INFO
Invalid 'expect_value': '$input_expect_value'
Must have the value of 'true' or 'false'.
END_OF_ERROR_INFO
            invalid_function_usage 0 'register_function_flags' "$error_info"
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
            invalid_function_usage 0 'register_function_flags' "$error_info"
            exit 1
        fi

        [[ -z "$input_short_flag" ]] && short_option+=("_") || short_option+=("$input_short_flag")
        [[ -z "$input_long_flag" ]] && long_option+=("_") || long_option+=("$input_long_flag")

        expect_value+=("$input_expect_value")
        description+=("$input_description")

        shift 4
    done

    ### Append to global arrays
    #
    # [*] used to save all '${ARRAY_SEPARATOR}' separated at the same index, to map all options
    # to the same registered function name
    local old_IFS="$IFS"
    IFS="${ARRAY_SEPARATOR}"
    _handle_args_registered_function_ids+=("$function_id")
    _handle_args_registered_function_short_option+=("${short_option[*]}")
    _handle_args_registered_function_long_option+=("${long_option[*]}")
    _handle_args_registered_function_values+=("${expect_value[*]}")
    _handle_args_registered_function_descriptions+=("${description[*]}")
    IFS="$old_IFS"
}

_handle_input_register_function_flags()
{
    _handle_args 'register_function_flags' "$@"

    function_id="${non_flagged_args[0]}"
}

# Register help text for a function
#
# The function will do the following if used correctly:
# 1. Add function id to
#       _handle_args_registered_help_text_function_ids[]
# 2. Add help text to
#       _handle_args_registered_help_text[]
#
register_help_text()
{
    local function_id
    local help_text

    # Special case for register_help_text(), manually parse for help flag
    _handle_input_register_help_text "$@"

    _validate_input_register_help_text

    _handle_args_registered_help_text_function_ids+=("$function_id")
    _handle_args_registered_help_text+=("$help_text")
}

_handle_input_register_help_text()
{
    _handle_args 'register_help_text' "$@"
    
    function_id="${non_flagged_args[0]}"
    help_text="${non_flagged_args[1]}"
}

_validate_input_register_help_text()
{
    if [[ -z "$function_id" ]]
    then
        define error_info <<END_OF_ERROR_INFO
Given <function_id> is empty.
END_OF_ERROR_INFO
        invalid_function_usage 1 'register_help_text' "$error_info"
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
            invalid_function_usage 1 'register_help_text' "$error_info"
            exit 1
        fi
    done

    if [[ -z "$help_text" ]]
    then
        define error_info <<END_OF_ERROR_INFO
Given <help_text> is empty.
END_OF_ERROR_INFO
        invalid_function_usage 1 'register_help_text' "$error_info"
        exit 1
    fi
}

# Process flags & non-optional arguments
_handle_args()
{
    check_for_help_flag '_handle_args' --strict-check-only-help-flag "$@"

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

    local allow_non_registered_flags_handle_args='false'
    for arg in "${arguments[@]}"
    do
        if [[ "$arg" == '--allow-non-registered-flags' ]]
        then
            allow_non_registered_flags_handle_args='true'
        fi
    done

    _validate_input_handle_args
    # Output:
    # function_index

    check_for_help_flag "$function_id" "${arguments[@]}"

    local valid_short_options
    local valid_long_options
    local flags_descriptions
    local expects_value
    # Convert space separated elements into an array
    IFS="${ARRAY_SEPARATOR}" read -ra valid_short_options <<< "${_handle_args_registered_function_short_option[function_index]}"
    IFS="${ARRAY_SEPARATOR}" read -ra valid_long_options <<< "${_handle_args_registered_function_long_option[function_index]}"
    IFS="${ARRAY_SEPARATOR}" read -ra flags_descriptions <<< "${_handle_args_registered_function_descriptions[function_index]}"
    IFS="${ARRAY_SEPARATOR}" read -ra expects_value <<< "${_handle_args_registered_function_values[function_index]}"

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
Registered flags through register_function_flags() must follow the valid_var_name() validation.
END_OF_ERROR_INFO


            # TODO: Replace with more general error
            invalid_function_usage 1 '' "$error_info" --manual-help-text "$function_usage"
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
                        invalid_function_usage 1 '' "$error_info" --manual-help-text "$function_usage"
                        exit 1
                    fi

                    # Store given value after flag
                    declare -g "${derived_flag_name}_value"="${arguments[i]}"
                fi

                was_option_handled='true'
                break
            fi
        done

        if [[ "$allow_non_registered_flags_handle_args" != 'true' &&
              "$was_option_handled" != 'true' ]]
        then
            define error_info <<END_OF_ERROR_INFO
Given flag '${arguments[i]}' is not registered for function id: '$function_id'

$(register_function_flags --help)
END_OF_ERROR_INFO

            error 1 '' "$error_info" --manual-help-text "$function_usage"
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
        invalid_function_usage 1 '' "$error_info" --manual-help-text "$function_usage"
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
        invalid_function_usage 1 '' "$error_info" --manual-help-text "$function_usage"
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
        invalid_function_usage 1 '' "$error_info" --manual-help-text "$function_usage"
        exit 1
    fi
}

unset _function_index_dumb_add
unset -f _add_separator_to_arrays_handle_args
unset -f _dumb_add_function_flags_and_help_text

################################################################################
################################################################################
##### ALLOW FUNCTION CALLS register_function_flags() & register_help_text()
#####
##### From below here, you can call
##### register_function_flags() & register_help_text()
##### This is because of circular dependencies if called before
################################################################################
################################################################################


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

        invalid_function_usage 1 '' "$error_info" --manual-help-text "$function_usage"
        exit 1
    fi
}

register_function_flags 'error'

register_help_text 'error' \
"error <functions_before>
        <function_id>
        <extra_info>

Output a generic error with backtrace, function definition, error info and help
text.

Arguments:
    <functions_before>:
        Used for the output 'Defined at' & 'Backtrace' sections.
        Which function which to mark with the error.
        - '0': The function calling invalid_function_usage()
        - '1': 1 function before that
        - '2': 2 functions before that
        - '#': etc.
    <function_id>:
        Used for the output 'Help text' section.
        Function ID used to register the function help text & flags:
        - register_hel main.sh sources script_1.invalid_function_p_test()
        - register_function_flags()
    <extra_info>:
        Single-/Multi-line with extra info.
        - Example:
            \"Invalid input <arg_two>: '\$arg_two'\"

All the rest of the arguments e.g. flags will be passed to _error_call(), see
the help text of _error_call() for more information.

Help text for _error_call():

$(get_help_text '_error_call')"

error()
{
    local functions_before
    local function_id
    local extra_info

    _handle_args_error "$@"
    shift 3

    declare -r PLACEHOLDER_FUNC_NAME='<__PLACEHOLDER_FUNC_NAME__>'
    local start_message="Error in ${PLACEHOLDER_FUNC_NAME}"

    # Pass potential flags with "$@"
    _error_call "$((functions_before + 1))" \
                "$function_id" \
                "$extra_info" \
                "$start_message" \
                --backtrace-level 1 \
                "$@"
}

_handle_args_error()
{
    _handle_args 'error' "$@"

    functions_before="${non_flagged_args[0]}"
    function_id="${non_flagged_args[1]}"
    extra_info="${non_flagged_args[2]}"

    # Validate to be number as we will manipulate it. Thereby a need to check it
    # before calling _error_call() instead of relying on its check
    _validate_functions_before_variable 'error' "$functions_before"
}

register_function_flags 'warning'

register_help_text 'warning' \
"warning <functions_before>
          <function_id>
          <extra_info>

Output a generic warning with backtrace, function definition, error info and
help text.

Arguments:
    <functions_before>:
        Used for the output 'Defined at' & 'Backtrace' sections.
        Which function which to mark with the error.
        - '0': The function calling invalid_function_usage()
        - '1': 1 function before that
        - '2': 2 functions before that
        - '#': etc.
    <function_id>:
        Used for the output 'Help text' section.
        Function ID used to register the function help text & flags:
        - register_hel main.sh sources script_1.invalid_function_p_test()
        - register_function_flags()
    <extra_info>:
        Single-/Multi-line with extra info.
        - Example:
            \"Invalid input <arg_two>: '\$arg_two'\"

All the rest of the arguments e.g. flags will be passed to _error_call(), see
the help text of _error_call() for more information.

Help text for _error_call():

$(get_help_text '_error_call')"

warning()
{
    local functions_before
    local function_id
    local extra_info

    _handle_args_warning "$@"
    shift 3

    declare -r PLACEHOLDER_FUNC_NAME='<__PLACEHOLDER_FUNC_NAME__>'
    local start_message="Warning in ${PLACEHOLDER_FUNC_NAME}"

    # Pass potential flags with "$@"
    _error_call "$((functions_before + 1))" \
                "$function_id" \
                "$extra_info" \
                "$start_message" \
                --backtrace-level 1 \
                "$@"
}

_handle_args_warning()
{
    _handle_args 'warning' "$@"

    functions_before="${non_flagged_args[0]}"
    function_id="${non_flagged_args[1]}"
    extra_info="${non_flagged_args[2]}"

    # Validate to be number as we will manipulate it. Thereby a need to check it
    # before calling _error_call() instead of relying on its check
    _validate_functions_before_variable 'warning' "$functions_before"
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
            invalid_function_usage 1 '' "$error_info" --manual-help-text "$function_usage"
            exit 1
            ;;
    esac

    # Validate <bash_source_array_len>
    case $bash_source_array_len in
        ''|*[!0-9]*)
define error_info <<END_OF_ERROR_INFO
Invalid input <bash_source_array_len>, not a number: '$bash_source_array_len'
END_OF_ERROR_INFO
            invalid_function_usage 1 '' "$error_info" --manual-help-text "$function_usage"
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

        invalid_function_usage 1 '' "$error_info" --manual-help-text "$function_usage"
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
