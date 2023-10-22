#####################
### Guard library ###
#####################
guard_source_max_once()
{
    valid_var_name() { grep -q '^[_[:alpha:]][_[:alpha:][:digit:]]*$' <<< "$1"; }

    local file_name="$(basename "${BASH_SOURCE[0]}")"
    local file_name_wo_extension="${file_name%.*}"
    local guard_var_name="guard_$file_name_wo_extension"

    if ! valid_var_name "$guard_var_name"
    then
        echo "Failed at creating valid variable name for guarding library."
        echo -e "File name: $file_name\nVariable name: $guard_var_name"
        exit 1
    fi

    [[ -n "${!guard_var_name}" ]] && return 1
    declare -gr "guard_$file_name_wo_extension=true"
}

guard_source_max_once || return

#####################
### Library start ###
#####################

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
    local function_usage="$2"
    local error_info="$3"

    _validate_input_invalid_function_usage "$@"
    # Output: Overrides all the variables when input is invalid

    local func_name="${FUNCNAME[functions_before]}"
    local func_def_file="${BASH_SOURCE[functions_before]}"
    local func_call_file="${BASH_SOURCE[functions_before+1]}"
    local func_call_line_num="${BASH_LINENO[functions_before]}"

    eval $(resize) # Update COLUMNS regardless if shopt checkwinsize is enabled
    local wrapper="$(printf "%.s#" $(seq $COLUMNS))"
    local divider="$(printf "%.s-" $(seq $COLUMNS))"

    local output_message
    define output_message <<END_OF_VARIABLE_WITH_EVAL

${wrapper}
!! Invalid usage of ${func_name}()

Called from:
${func_call_line_num}: ${func_call_file}

Whole backtrace:
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
    [[ "$input_error_this_func" == 'true' ]] && exit 1
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

    local invalid_usage_of_this_func='false'

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
