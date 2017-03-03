let s:plugin_hints = [
      \ 'autoload',
      \ 'colors',
      \ 'compiler',
      \ 'ftplugin',
      \ 'filetype.vim',
      \ 'indent',
      \ 'keymap',
      \ 'plugin',
      \ 'rplugin',
      \ 'syntax',
      \ ]

let s:levels = [
      \ 'Flawless Victory',
      \ 'Outstanding',
      \ 'Fatality',
      \ 'Toasty',
      \ 'Impressive',
      \ 'Well Done',
      \ 'Test your might',
      \ ]


function! s:plugin_sort(a, b) abort
  return len(a:b[0]) - len(a:a[0])
endfunction


function! s:result_sort(a, b) abort
  if a:a[1] < a:b[1]
    return 1
  elseif a:a[1] > a:b[1]
    return -1
  endif
  return 0
endfunction


function! s:init_plugins() abort
  let vimrc_path = fnamemodify(expand('$MYVIMRC'), ':p:h')
  let runtime_path = expand('$VIMRUNTIME')
  let s:plugins = []

  for path in split(&runtimepath, ',')
    let path = fnamemodify(path, ':p')
    if path =~# '/$'
      let path = path[:-2]
    endif

    if path =~# '/after$'
      let path = fnamemodify(path, ':h')
      if path =~# '/$'
        let path = path[:-2]
      endif
    endif

    if path != vimrc_path && path != runtime_path
      for hint in s:plugin_hints
        let hint_path = path . '/' . hint
        if isdirectory(hint_path) || filereadable(hint_path)
          let name = fnamemodify(path, ':t')
          call add(s:plugins, [path . '/', name])
          break
        endif
      endfor
    endif
  endfor

  call sort(s:plugins, function('s:plugin_sort'))
  call add(s:plugins, [vimrc_path . '/', '[vimrc]'])
  call add(s:plugins, [runtime_path . '/', '[runtime]'])
endfunction


function! s:get_plugin(fname) abort
  for [path, name] in s:plugins
    if len(path) < len(a:fname) && a:fname[:len(path)-1] == path
      return name
    endif
  endfor

  return '[unknown]'
endfunction


function! s:get_samples(cmd, count, tmp) abort
  let c = 0
  let phase_order = []
  let phases = {'startup': {'_files': {}, '_time': 0}}
  let totals = {}
  let total_time = 0

  while c < a:count
    let c += 1
    redraw
    echo 'Sample' c
    call system(a:cmd)

    if !filereadable(a:tmp)
      echohl ErrorMsg
      echo 'Profile log wasn''t created'
      echohl None
      break
    endif

    let phase = 'startup'

    for line in readfile(a:tmp)
      if line =~# '^\%(\d\+\.\d\+\s*\)\{2}:'
        if c == 1
          call add(phase_order, phase)
        endif
        " call add(phases, {'phase': phase, 'times': cur_phase})
        " let cur_phase = {}
        let phase = matchstr(line, '\d\+\.\d\+: \zs.*')
        if !has_key(phases, phase)
          let phases[phase] = {'_files': {}, '_time': 0}
        endif
      elseif line =~# '^\%(\d\+\.\d\+\s*\)\{3}: sourcing '
        let [time, fname] = split(matchstr(line, '\d\+\.\d\+: .*'), ':\s*sourcing\s*')
        let plugin = s:get_plugin(fname)

        if !has_key(phases[phase], plugin)
          let phases[phase][plugin] = 0
          let phases[phase]['_files'][plugin] = {}
        endif

        if !has_key(phases[phase]['_files'][plugin], fname)
          let phases[phase]['_files'][plugin][fname] = 0
        endif

        if !has_key(totals, plugin)
          let totals[plugin] = 0
        endif

        let t = str2float(time)
        let phases[phase][plugin] += t
        let phases[phase]['_time'] += t
        let phases[phase]['_files'][plugin][fname] += t
        let totals[plugin] += t
        let total_time += t
      endif
    endfor

    call delete(a:tmp)
  endwhile

  for phase in keys(phases)
    for plugin in keys(phases[phase])
      if plugin != '_files'
        let phases[phase][plugin] = phases[phase][plugin] / c
      else
        for fplugin in keys(phases[phase][plugin])
          for fname in keys(phases[phase][plugin][fplugin])
            let phases[phase][plugin][fplugin][fname] = phases[phase][plugin][fplugin][fname] / c
          endfor
        endfor
      endif
    endfor
  endfor

  for plugin in keys(totals)
    let totals[plugin] = totals[plugin] / c
  endfor

  let total_time = total_time / c

  return [total_time, totals, phase_order, phases]
endfunction


function! startuptime#profile(...) abort
  let sample_count = 10
  if a:0 && type(a:1) == type(0) && a:1 > 0
    let sample_count = a:1
  endif

  call s:init_plugins()

  if executable('ps')
    let exe = split(system('ps -o command= -p ' . getpid()))[0]
  else
    let exe = has('nvim') ? 'nvim' : 'vim'
  endif

  let tmp = tempname()
  " Use `script` so Vim doesn't issue a delay warning
  let cmd = 'script -q -c "' . exe . ' --startuptime ' . tmp . ' +:qa!" /dev/null'


  let [total_time, totals, phase_order, phases] = s:get_samples(cmd, sample_count, tmp)
  let level_time = 1000 / (len(s:levels) - 1)
  let l = float2nr(floor(min([float2nr(total_time), 1000]) / level_time))
  let level = s:levels[l]

  let lines = [printf('Total Time: %-8.3f -- %s', total_time, level), '']

  let slowest = sort(items(totals), function('s:result_sort'))[:9]
  let width = max(map(copy(slowest), 'len(v:val[0])'))
  let lines += ['', printf('Slowest %d plugins (out of %d)~', len(slowest), len(totals))]

  for [plugin, time] in slowest
    call add(lines, printf("%*s\t%-8.3f", width, plugin, time))
  endfor

  let lines += ['', 'Phase Detail:~', '']

  for phase in phase_order
    let item = phases[phase]
    let files = remove(item, '_files')
    let phase_total = remove(item, '_time')

    if empty(item)
      continue
    endif

    let lines += [printf('%s (%0.3f)~', phase, phase_total)]
    for [plugin, time] in sort(items(item), function('s:result_sort'))
      let lines += [printf("%-8.3f  %s >", time, plugin)]
      for [fname, time] in sort(items(files[plugin]), function('s:result_sort'))
        let lines += [printf("\t%-8.3f  %s", time, fname)]
      endfor
      let lines += ['<']
    endfor
    let lines += ['']
  endfor

  enew
  silent %put=lines
  call cursor(1, 1)
  delete _
  set buftype=nofile syntax=help foldmethod=marker foldmarker=>,< nomodified
  normal! zM
endfunction