require "db_utils"
require "rollup_methods"

class AnalyticUtils

  # TODO: Change to use parameterized queries
  # NOTE: You cannot have multiple group_by's and also have show_rollup_remainder = true
  #
  # Table of possible analytics queries
  # ------------------------------------------------------------------------------------------
  # | Rollup | # of Group Bys | Show Remainder |                   Result                    |
  # ------------------------------------------------------------------------------------------
  # |    N   |       -        |       -        | No Limits needed                            |
  # |    Y   |      0-1       |       N        | Simple single limit case                    |
  # |    Y   |      2+        |       N        | Cannot use limit so need to use inner query |
  # |    Y   |      0-1       |       Y        | Have to use two limit queries               |
  # |    Y   |      2+        |       Y        | NOT SUPPORTED                               |
  # ------------------------------------------------------------------------------------------
  def self.get_analytics_data(label_columns, data_column, metric_tables,
                              rollup_method, rollup_count, show_rollup_remainder,
                              order_via_group_bys, search_criteria = nil)

    sql_stmt = get_base_analytics_data(label_columns, data_column, metric_tables,
                              rollup_method, rollup_count, show_rollup_remainder,
                              order_via_group_bys, search_criteria, true)

    # If we're planning to show the rollup remainder then we need to do the limit the other way
    if !rollup_count.nil? && show_rollup_remainder
      top_x_query = sql_stmt
      base_others_query = get_base_analytics_data(label_columns, data_column, metric_tables,
                            rollup_method, rollup_count, show_rollup_remainder,
                            order_via_group_bys, search_criteria, false) 

      # TODO: Change SUM to other rollup_aggregation_method
      others_query = "(SELECT 'others' as #{label_columns[0][:alias]}, " \
        "SUM(#{data_column[:alias]}) #{data_column[:alias]} " \
        "FROM (#{base_others_query}) others_tbl " \
        "HAVING #{data_column[:alias]} IS NOT NULL) "
      sql_stmt = "(#{top_x_query}) UNION (#{others_query})"
    end

    return ActiveRecord::Base.connection.exec_query(sql_stmt)
  end

  def self.get_base_analytics_data(label_columns, data_column, metric_tables,
                              rollup_method, rollup_count, show_rollup_remainder,
                              order_via_group_bys, search_criteria, inner_limit_top )
    select_label_cols = label_columns.map {|column| "#{column[:sql_select]} #{column[:alias]}"}
    group_by_label_cols = label_columns.map {|column| column[:alias]}
    select_data_col = "#{data_column[:sql_select]} #{data_column[:alias]}"

    sql_stmt = "SELECT #{select_label_cols.join(", ")}, #{select_data_col} FROM #{metric_tables}"

    if !rollup_count.nil?
      sql_stmt += inner_join_rollup(select_label_cols, select_data_col,
                    label_columns, data_column, metric_tables,
                    rollup_method, rollup_count, inner_limit_top)
    end

    sql_stmt += where_clause_stmt(search_criteria)
    sql_stmt += "GROUP BY #{group_by_label_cols.join(", ")} "

    # If rolling up with multiple group bys or if label should sort by group_by then order by group bys
    if order_via_group_bys || label_columns[0][:sort_by] == 'group_by'
      group_by_order_str = group_by_label_cols.join(" #{rollup_method[:sort_order]}, ")
      sql_stmt += "ORDER BY #{group_by_order_str} #{rollup_method[:sort_order]} "
    else
      sql_stmt += "ORDER BY #{data_column[:alias]} #{rollup_method[:sort_order]} "
    end

    return sql_stmt
  end

  def self.inner_join_rollup(select_label_cols, select_data_col,
    label_columns, data_column, metric_tables,
    rollup_method, rollup_count, inner_limit_top)

    inner_join = "INNER JOIN (SELECT #{select_label_cols[0]}, "
    
    if rollup_method[:rollup_by]
      inner_join += "#{rollup_method[:rollup_by][:sql_select]} #{rollup_method[:rollup_by][:alias]} "
    else
      inner_join += "#{select_data_col} "
    end

    inner_join += "FROM #{metric_tables} " \
      "WHERE #{label_columns[0][:sql_select]} IS NOT NULL " \
      "GROUP BY #{label_columns[0][:alias]} "

    if rollup_method[:rollup_by]
      inner_join += "ORDER BY #{rollup_method[:rollup_by][:alias]} #{rollup_method[:sort_order]} "
    else
      inner_join += "ORDER BY #{data_column[:alias]} #{rollup_method[:sort_order]} "
    end

    if inner_limit_top
      inner_join += "LIMIT #{rollup_count} "
    else
      inner_join += "LIMIT #{rollup_count}, 18446744073709551615 "
    end

    inner_join += ") rollup_val_tbl ON rollup_val_tbl.#{label_columns[0][:alias]} = #{label_columns[0][:sql_select]} "

    return inner_join
  end




  def self.get_pull_request_data(search_criteria = nil)

    sql_stmt = "SELECT pr.pr_number, pr.title, pr.body, pr.state, IFNULL(NULLIF(u.name, ''), u.login) user_name, c.name company, r.name repo_name,  " \
      "r.full_name repo_full_name, pr.date_created, pr.date_closed, pr.date_merged, #{DBUtils.get_date_difference('pr.date_closed','pr.date_created')} days_open " \
      "FROM pull_requests pr " \
      "LEFT OUTER JOIN users u ON pr.user_id = u.id " \
      "LEFT OUTER JOIN companies c ON u.company_id = c.id " \
      "LEFT OUTER JOIN repos r ON pr.repo_id = r.id " \
      "LEFT OUTER JOIN orgs o ON r.org_id = o.id "

    sql_stmt += where_clause_stmt(search_criteria)

    sql_stmt += "ORDER BY user_name, pr.date_created"

    return ActiveRecord::Base.connection.exec_query(sql_stmt)
  end

  # Input array must be [{label_index_name => label, data_index_name => data}]
  def self.top_x_with_rollup(input_array, label_index_name, data_index_name, top_x_count, rollup_name, rollup_method)
    if top_x_count < 0
      top_x_count = 0
    end

    if top_x_count >= input_array.count
      return input_array
    end

    # Sort the array
    sorted_array = input_array.sort_by {|x| x[data_index_name] }.reverse

    # Calculate the remaining
    rollup_val = 0
    if rollup_method == ROLLUP_METHOD::SUM
      sorted_array[top_x_count..sorted_array.count].each {|x| rollup_val += x[data_index_name] }
    elsif rollup_method == ROLLUP_METHOD::AVG
      sorted_array[top_x_count..sorted_array.count].each {|x| rollup_val += x[data_index_name] }
      rollup_val = rollup_val / (sorted_array.count - top_x_count)
    else
      puts "ERROR: Unknown Rollup Method '#{rollup_method}'"
    end
    
    # Remove non-top
    result = sorted_array[0...top_x_count]

    # Add rollup record
    # Add the numbers for mysql
    result << {label_index_name => rollup_name, data_index_name => rollup_val}

    return result
  end

  def self.clean()

  end

  def self.where_clause_stmt(search_criteria, metric = nil)

    # If there is no search criteria, just return
    puts "SEARCH CRITERIA #{search_criteria}"
    return "" unless search_criteria
    puts "SEARCH CRITERIA CLASS #{search_criteria.class}"
    where_stmt = " WHERE 1=1 "

    #ActionController::Parameters.permit_all_parameters = true

    # When clicking on the "Uncheck All" button, 
    # search_criteria.each do |filter|
    #   puts "FILTER ARRAY #{filter}, VALUE #{filter[1]} , CLASS #{filter[1].class}"
    #   val = filter[1]
    #   #filter[1].is_a?(String) ?  :
    #   #filter.map! {|x| y.is_a?(String) ? Array[y] : y  ; puts y }
    #   if val.is_a?(String) #&& filter[1].strip.length == 0) #== "String"        
    #     filter.pop
    #     filter.push(Array[val])
    #   end
    #   puts "#{filter}"
    # end

    # puts "_________________________________"
    # search_criteria.each { |filter|
    #   puts "MODIFIED FILTER ARRAY #{filter}, VALUE #{filter[1]} , CLASS #{filter[1].class}"
    # }


    if search_criteria[:month] && search_criteria[:month].join != ''
      where_stmt += "AND #{DBUtils.get_month('pr.date_created')} IN ('#{search_criteria[:month].join("', '")}') "
    end

    if search_criteria[:quarter] && search_criteria[:quarter].join != ''
      where_stmt += "AND #{DBUtils.get_month('pr.date_created')} IN ("
      search_criteria[:quarter].each {|quarter|
        case quarter
          when "q1"
            where_stmt += "'01', '02', '03',"
          when "q2"
            where_stmt += "'04', '05', '06',"
          when "q3"
            where_stmt += "'07', '08', '09',"
          when "q4"
            where_stmt += "'10', '11', '12',"
        end
      }
      where_stmt = where_stmt.chop + ")"
    end

    if search_criteria[:year] && search_criteria[:year].join != ''
      where_stmt += "AND #{DBUtils.get_year('pr.date_created')} IN ('#{search_criteria[:year].join("', '")}') "
    end

    if search_criteria[:start_date] && search_criteria[:start_date] != ''
      start_date = search_criteria[:start_date]

      if start_date.include?("/")
        start_date = DateUtils.human_slash_date_format_to_db_format(start_date)
      end
      
      where_stmt += "AND pr.date_created >= '#{start_date}' "
    end

    if search_criteria[:end_date] && search_criteria[:end_date] != ''
      end_date = search_criteria[:end_date]
      
      if end_date.include?("/")
        end_date = DateUtils.human_slash_date_format_to_db_format(end_date)
      end

      where_stmt += "AND pr.date_created <= '#{end_date}'  "
    end

    if search_criteria[:repo] && search_criteria[:repo].join != ''
      where_stmt += "AND r.name IN ('#{search_criteria[:repo].join("', '")}') "
    end

    if search_criteria[:state]
      search_criteria[:state].each {|state|
        if state == 'open'
          where_stmt += "AND pr.state = 'open' "
        elsif state == 'merged'
          where_stmt += "AND pr.date_merged IS NOT NULL "
        elsif state == 'closed'
          # Not including merged prs
          where_stmt += "AND pr.state = 'closed' AND pr.date_merged IS NULL "
        end
      }
    end

    # TODO, See if 
    if search_criteria[:company] && search_criteria[:company].join != ''
      where_stmt += "AND c.name IN ('#{(search_criteria[:company]).join("', '")}') "
    end


    if search_criteria[:user] && search_criteria[:user].join != ''
      where_stmt += "AND u.login IN ('#{(search_criteria[:user]).join("', '")}') "
    end

    #search_criteria[:name] = [search_criteria[:name]] if search_criteria[:name].class == "String"
    if search_criteria[:name] && search_criteria[:name].join != ''
      where_stmt += "AND u.name IN ('#{(search_criteria[:name]).join("', '")}') "
    end

    if search_criteria[:org] && search_criteria[:org].join != ''
      where_stmt += "AND o.login IN ('#{(search_criteria[:org]).join("', '")}') "
    end
    return where_stmt
  end

  def self.get_state_stats(data)
    total = 0
    open = 0
    closed = 0
    merged = 0
    data.each { |x|
      total += 1
      if x['date_merged']
        merged += 1
      elsif x['date_closed']
        closed += 1
      else
        open += 1
      end
    }

    return {:total => total, :open => open, :closed => closed, :merged => merged}
  end
end