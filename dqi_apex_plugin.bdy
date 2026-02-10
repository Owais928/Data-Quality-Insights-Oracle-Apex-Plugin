create or replace package body dqi_apex_plugin as

  function csv_to_list(p_csv varchar2) return apex_t_varchar2 is
    l_list apex_t_varchar2 := apex_t_varchar2();
    l_idx  pls_integer := 1;
    l_val  varchar2(4000);
  begin
    if p_csv is null then
      return l_list;
    end if;

    loop
      l_val := trim(regexp_substr(p_csv, '[^,]+', 1, l_idx));
      exit when l_val is null;
      l_list.extend;
      l_list(l_list.count) := l_val;
      l_idx := l_idx + 1;
    end loop;

    return l_list;
  end;

  function safe_col(p_col varchar2) return varchar2 is
    l_col varchar2(4000) := upper(trim(p_col));
  begin
    if l_col is null then
      raise_application_error(-20000, 'Column name is empty.');
    end if;

    -- allow: COL or ALIAS.COL
    if not regexp_like(l_col, '^[A-Z0-9_#$]+(\.[A-Z0-9_#$]+)?$') then
      raise_application_error(-20001, 'Invalid column identifier: ' || p_col);
    end if;

    return l_col;
  end;

  function col_key(p_col varchar2) return varchar2 is
  begin
    return upper(regexp_substr(p_col, '[^\.]+$', 1, 1));
  end;

  function to_num(p_str varchar2, p_default number) return number is
  begin
    return to_number(trim(p_str));
  exception
    when others then
      return p_default;
  end;

  function get_regex_for_col(p_rules_json clob, p_col_upper varchar2) return varchar2 is
  begin
    if p_rules_json is null then
      return null;
    end if;

    apex_json.parse(p_rules_json);
    return apex_json.get_varchar2(p_col_upper);
  exception
    when others then
      return null; -- keep resilient if bad JSON
  end;

  procedure ajax_region(
    p_region in apex_plugin.t_region,
    p_plugin in apex_plugin.t_plugin,
    p_param  in apex_plugin.t_region_ajax_param,
    p_result in out nocopy apex_plugin.t_region_ajax_result
  ) is
    /*l_sql_query   clob := p_region.attribute_01;          -- required
    l_cols_csv    varchar2(4000) := p_region.attribute_02;-- required
    l_sample_rows number := to_num(p_region.attribute_03, 5000);

    l_warn_null   number := to_num(p_region.attribute_04, 5);
    l_err_null    number := to_num(p_region.attribute_05, 20);
    l_warn_dup    number := to_num(p_region.attribute_06, 1);
    l_err_dup     number := to_num(p_region.attribute_07, 5);

    l_rules_json  clob := p_region.attribute_08; -- optional*/
    l_sql_query   clob;
    l_cols_csv    varchar2(4000);
    l_rules_json  clob;

    l_sample_rows number;
    l_warn_null   number;
    l_err_null    number;
    l_warn_dup    number;
    l_err_dup     number;
    
    l_cols apex_t_varchar2;-- := csv_to_list(l_cols_csv);

    l_select_cols clob := 'count(*) as TOTAL_ROWS';
    l_dynamic_sql clob;

    -- dbms_sql
    l_c integer;
    l_colcnt integer;
    l_desc dbms_sql.desc_tab2;
    l_num number;

    type t_num_map is table of number index by varchar2(200);
    l_numbers t_num_map;

    -- regex map
    type t_pat_map is table of varchar2(4000) index by varchar2(200);
    l_pat_map t_pat_map;

    l_col_safe varchar2(4000);
    l_key      varchar2(200);
    l_pat      varchar2(4000);
    l_exec integer;
    l_warn_inv number;
    l_err_inv  number;
  begin
    l_sql_query := p_region.attributes.get_varchar2('sql_query',        p_do_substitutions => true);
    l_cols_csv  := p_region.attributes.get_varchar2('columns_csv',      p_do_substitutions => true);
    l_rules_json:= p_region.attributes.get_varchar2('regex_rules_json', p_do_substitutions => true);

    l_sample_rows := to_num(p_region.attributes.get_varchar2('sample_rows'),      5000);
    l_warn_null   := to_num(p_region.attributes.get_varchar2('warn_null'),        5);
    l_err_null    := to_num(p_region.attributes.get_varchar2('error_null'),       20);
    l_warn_dup    := to_num(p_region.attributes.get_varchar2('warn_duplicate'),   1);
    l_err_dup     := to_num(p_region.attributes.get_varchar2('error_duplicate'),  5);
    l_warn_inv    := to_num(p_region.attributes.get_varchar2('warn_invalid'), 5);
    l_err_inv     := to_num(p_region.attributes.get_varchar2('error_invalid'), 20);
    l_cols := csv_to_list(l_cols_csv);
    if l_sql_query is null then
      apex_json.open_object;
      apex_json.write('status', 'error');
      apex_json.write('message', 'Attribute 1 (SQL Query) is required.');
      apex_json.close_object;
      return;
    end if;

    if l_cols.count = 0 then
      apex_json.open_object;
      apex_json.write('status', 'error');
      apex_json.write('message', 'Attribute 2 (Columns CSV) is required.');
      apex_json.close_object;
      return;
    end if;

    -- build regex map first
    for i in 1 .. l_cols.count loop
      l_col_safe := safe_col(l_cols(i));
      l_key := col_key(l_col_safe);
      l_pat_map(l_key) := get_regex_for_col(l_rules_json, l_key);
    end loop;

    -- build select list
    for i in 1 .. l_cols.count loop
      l_col_safe := safe_col(l_cols(i));
      l_key := col_key(l_col_safe);

      l_select_cols := l_select_cols
        || ', sum(case when '||l_col_safe||' is null then 1 else 0 end) as NULLS_'||l_key
        || ', count('||l_col_safe||') as NONNULL_'||l_key
        || ', count(distinct '||l_col_safe||') as DISTINCT_'||l_key;

      if l_pat_map(l_key) is not null then
        l_select_cols := l_select_cols
          || ', sum(case when '||l_col_safe||' is not null'
          || ' and not regexp_like(to_char('||l_col_safe||'), :PAT_'||l_key||')'
          || ' then 1 else 0 end) as INVALIDS_'||l_key;
      else
        l_select_cols := l_select_cols || ', 0 as INVALIDS_'||l_key;
      end if;
    end loop;

    l_dynamic_sql :=
      'with src as ('||chr(10)|| l_sql_query ||chr(10)||') '||
      'select '|| chr(10) || l_select_cols || chr(10) ||
      'from (select * from src fetch first :SAMPLE_ROWS rows only)';

    -- execute with DBMS_SQL (supports optional binds)
    l_c := dbms_sql.open_cursor;
    dbms_sql.parse(l_c, l_dynamic_sql, dbms_sql.native);

    dbms_sql.bind_variable(l_c, ':SAMPLE_ROWS', l_sample_rows);

    for i in 1 .. l_cols.count loop
      l_col_safe := safe_col(l_cols(i));
      l_key := col_key(l_col_safe);
      l_pat := l_pat_map(l_key);
      if l_pat is not null then
        dbms_sql.bind_variable(l_c, ':PAT_'||l_key, l_pat);
      end if;
    end loop;

    dbms_sql.describe_columns2(l_c, l_colcnt, l_desc);

    for i in 1 .. l_colcnt loop
      dbms_sql.define_column(l_c, i, l_num);
    end loop;

    l_exec := dbms_sql.execute(l_c);
    if dbms_sql.fetch_rows(l_c) > 0 then
      for i in 1 .. l_colcnt loop
        dbms_sql.column_value(l_c, i, l_num);
        l_numbers(upper(l_desc(i).col_name)) := l_num;
      end loop;
    end if;

    dbms_sql.close_cursor(l_c);

    -- output JSON
    declare
      l_total number := nvl(l_numbers('TOTAL_ROWS'), 0);
      l_status varchar2(10);
      l_nulls number;
      l_nonnull number;
      l_dist number;
      l_inv number;
      l_dups number;
      l_null_pct number;
      l_dup_pct number;
      l_inv_pct number;
    begin
      apex_json.open_object;
      apex_json.write('status', 'ok');
      apex_json.write('total_rows', l_total);
      apex_json.write('sample_rows', l_sample_rows);
      apex_json.open_array('columns');

      for i in 1 .. l_cols.count loop
        l_col_safe := safe_col(l_cols(i));
        l_key := col_key(l_col_safe);

        l_nulls   := nvl(l_numbers('NULLS_'||l_key), 0);
        l_nonnull := nvl(l_numbers('NONNULL_'||l_key), 0);
        l_dist    := nvl(l_numbers('DISTINCT_'||l_key), 0);
        l_inv     := nvl(l_numbers('INVALIDS_'||l_key), 0);
        l_dups    := greatest(l_nonnull - l_dist, 0);

        l_null_pct := case when l_total = 0 then 0 else round((l_nulls / l_total) * 100, 2) end;
        l_dup_pct  := case when l_nonnull = 0 then 0 else round((l_dups  / l_nonnull) * 100, 2) end;
        l_inv_pct  := case when l_nonnull = 0 then 0 else round((l_inv   / l_nonnull) * 100, 2) end;

        /*l_status := 'good';

        if l_null_pct >= l_err_null
           or l_dup_pct >= l_err_dup
           or l_inv_pct >= l_err_inv
        then
          l_status := 'bad';

        elsif l_null_pct >= l_warn_null
           or l_dup_pct >= l_warn_dup
           or l_inv_pct >= l_warn_inv
        then
          l_status := 'warn';
        end if;*/

        l_status := 'good';
        if l_null_pct >= l_err_null or l_dup_pct >= l_err_dup or l_inv_pct >= l_err_inv then
          l_status := 'bad';
        elsif l_null_pct >= l_warn_null or l_dup_pct >= l_warn_dup or l_inv_pct >= l_warn_inv then
          l_status := 'warn';
        end if;

        apex_json.open_object;
        apex_json.write('label', l_key);
        apex_json.write('expression', l_col_safe);
        apex_json.write('status', l_status);

        apex_json.write('total_rows', l_total);
        apex_json.write('nonnull', l_nonnull);
        apex_json.write('nulls', l_nulls);
        apex_json.write('distinct', l_dist);
        apex_json.write('duplicates', l_dups);
        apex_json.write('invalids', l_inv);

        apex_json.write('null_pct', l_null_pct);
        apex_json.write('dup_pct', l_dup_pct);
        apex_json.write('invalid_pct', l_inv_pct);
        apex_json.close_object;
      end loop;

      apex_json.close_array;
      apex_json.close_object;
    end;

  exception
    when others then
      if dbms_sql.is_open(l_c) then
        dbms_sql.close_cursor(l_c);
      end if;
      apex_json.open_object;
      apex_json.write('status', 'error');
      apex_json.write('message', sqlerrm);
      apex_json.close_object;
  end ajax_region;

  procedure render_region(
  p_region in apex_plugin.t_region,
  p_plugin in apex_plugin.t_plugin,
  p_param  in apex_plugin.t_region_render_param,
  p_result in out nocopy apex_plugin.t_region_render_result
) is
  l_region_id varchar2(200) := nvl(p_region.static_id, 'DQI_'||p_region.id);
  l_ajax_id   varchar2(4000) := apex_plugin.get_ajax_identifier;
begin
  -- Load plugin files
  apex_css.add_file(
    p_name      => 'dqi',
    p_directory => p_plugin.file_prefix
  );

  apex_javascript.add_library(
    p_name      => 'dqi',
    p_directory => p_plugin.file_prefix
  );

  -- Region container
  htp.p(
    '<div class="dqi" id="'||apex_escape.html_attribute(l_region_id)||'">'||
      '<div class="dqi-loading">Loading Data Quality Insights…</div>'||
    '</div>'
  );

  -- ✅ Inline init: runs when the region HTML is inserted (works with Deferred Loading too)
  htp.p(
    '<script>'||
    '(function(){'||
    '  var rid='||apex_escape.js_literal(l_region_id)||';'||
    '  var ajax='||apex_escape.js_literal(l_ajax_id)||';'||
    '  function go(){'||
    '    if(window.DQI && DQI.init){'||
    '      DQI.init({regionId: rid, ajaxId: ajax});'||
    '    } else {'||
    '      setTimeout(go, 50);'||
    '    }'||
    '  }'||
    '  go();'||
    '  if(window.apex && apex.jQuery){'||
    '    apex.jQuery("#"+rid).off("apexafterrefresh.dqi").on("apexafterrefresh.dqi", function(){ go(); });'||
    '  }'||
    '})();'||
    '</script>'
  );
end render_region;

end dqi_apex_plugin;
/
