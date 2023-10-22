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
    local function_usage="$2"
    local error_info="$3"

    _validate_input_invalid_function_usage "$@"
    # Output: Overrides all the variables when input is invalid

    local func_name="${FUNCNAME[functions_before]}"
    local func_def_file="${BASH_SOURCE[functions_before]}"
    local func_def_line_num="$(get_func_def_line_num $func_name $func_def_file)"
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
Defined at:
${func_def_line_num}: ${func_def_file}

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
