class AnalyticUtils
  def self.get_pull_request_stats(group_by_col, data_index_name, timeframe = nil, year = nil, repo=nil)
    sql_stmt = "SELECT #{group_by_col}, COUNT(*) #{data_index_name} FROM pull_requests pr " \
      "LEFT OUTER JOIN users u ON pr.user_id = u.id " \
      "LEFT OUTER JOIN companies c ON u.company_id = c.id " \
      "LEFT OUTER JOIN repos r ON pr.repo_id = r.id " \
      "WHERE 1 = 1 "

    if timeframe && timeframe != ''
      case timeframe
      when "q1"
        sql_stmt += "AND strftime('%m', pr.date_created) IN ('01', '02', '03') "
      when "q2"
        sql_stmt += "AND strftime('%m', pr.date_created) IN ('04', '05', '06') "
      when "q3"
        sql_stmt += "AND strftime('%m', pr.date_created) IN ('07', '08', '09') "
      when "q4"
        sql_stmt += "AND strftime('%m', pr.date_created) IN ('10', '11', '12') "
      end
    end

    if year && year != ''
      sql_stmt += "AND strftime('%Y', pr.date_created) IS '#{year}' "
    end

    if repo && repo != ''
      sql_stmt += "AND r.name IS '#{repo}' "
    end

    sql_stmt += "GROUP BY #{group_by_col} ORDER BY #{data_index_name} DESC"

    return ActiveRecord::Base.connection.execute(sql_stmt)
  end

  def self.get_pr_days_elapsed
    sql_stmt = "SELECT c.name, round(avg(julianday(IFNULL(pr.date_closed, date('now'))) - " \
      "julianday(pr.date_created)), 1) avg_days_open FROM pull_requests pr LEFT OUTER JOIN users u " \
      "ON pr.user_id = u.id LEFT OUTER JOIN companies c ON u.company_id = c.id GROUP BY c.name ORDER " \
      "BY c.name"

    return ActiveRecord::Base.connection.execute(sql_stmt)

  end

  def self.top_x_with_rollup(input_array, label_index_name, data_index_name, top_x_count, rollup_name)
    if top_x_count < 0
      top_x_count = 0
    end

    if top_x_count >= input_array.length
      return input_array
    else
      # Sort the array
      sorted_array = input_array.sort_by {|x| x[data_index_name] }.reverse

      # Calculate sum of remaining
      rollup_val = 0
      sorted_array[top_x_count..sorted_array.length].each {|x| rollup_val += x[data_index_name] }

      # Remove non-top
      result = sorted_array[0...top_x_count]

      # Add rollup record

      result << {label_index_name => rollup_name, data_index_name => rollup_val}

      return result
    end
  end
end