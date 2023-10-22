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
