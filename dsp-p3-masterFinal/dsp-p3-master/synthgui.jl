#needs multi-threading, thus, call julia -t 4 beforehand
# the velocity 6 is the most verossimile.



using Gtk, Dates, PortAudio

include("synthwrite.jl")
include("transcriber.jl")
# include("recording.jl")

NUM_ROWS = 6
NUM_COLS = 35
WRAP = false
styles = GtkCssProvider(data="
  * {
    font-family: Tahoma;
  }
  #header {
    padding: 10px;
    margin: 10px;
    font-size: 30px;
    font-weight: bold;
    color: white;
  }
  #timer-label {
    padding: 10px;
    margin: 10px;
    font-size: 30px;
    font-weight: bold;
    color: black;
  }
  #header-box {
    background: #00274C;
  }
  #tempo-label {
    padding: 5px;
    font-size: 20px;
    margin: 10px;
    background: transparent;
    color: white;
  }
  #export-button {
    margin: 10px;
    margin-bottom: 10px;
    margin-top: 10px;
    padding-top: 2px;
    padding-bottom: 2px;
    padding-left: 10px;
    padding-right: 10px;
    font-size: 20px;
    background: white;
    color: black;
    outline: none;
    box-shadow: none;
    text-shadow: none;
    border-radius: 5px;
    border-color: black;
    border-width: 2px;
  }
  #wrap-button {
    padding: 10px;
    font-size: 15px;
    margin: 5px;
    background: #00274C;
    color: white;
  }
  #note {
    padding: 5px 0px 5px 5px;
    margin-left: 20px;
    font-size: 20px;
    font-weight: bold;
  }
  #input {
    font-size: 20px;
    border: none;
    border-radius: 0;
    caret-color: transparent;
  }
  #input:focus {
    background: #f0f0f0;
  }
  #tempo-button {
    padding: 3px;
    font-size: 20px;
    background: #00274C;
    color: white;
    border-radius: 0;
    border-color: white;
    border-width: 1px;
  }
  #header-box {
  }
  #grid {
    padding: 20px;
    padding-left: 5px;
  }
  #text-view {
    font-size: 20px;
    padding: 10px;
    margin: 10px;
    font-family: Courier New;
  }
  #separator {
    border-top: 2px solid #00274C;
    padding: 0;
    margin-bottom: 0;
    margin-top: 10;
    margin-left: 15;
    margin-right: 15;
  }
  #footer {
    background: white;
    padding: 10px;
    padding-bottom: 15px;
  }

")

mutable struct MyState
  task::Union{Task,Nothing}
  someCounter::Int
end

function styled(widget, name)
  push!(GAccessor.style_context(widget), GtkStyleProvider(styles), 600)
  set_gtk_property!(widget, :name, name)
end

function async_set(obj, str)
  @sigatom @async begin
    @sigatom set_gtk_property!(obj, :text, str)
  end
end

function get_index_of(widget, grid)
  for i in range(1, NUM_ROWS)
    for j in range(1, NUM_COLS)
      if grid[j, i] == widget
        return (i, j)
      end
    end
  end
  return (0, 0)
end

function create_main_window()
  win = GtkWindow("Home")
  set_gtk_property!(win, :window_position, Gtk.GtkWindowPosition.CENTER)
  vbox_main = GtkBox(:v)
  image = GtkImage("logo2.png")

  transcriber = styled(GtkButton("Transcriber"), "export-button")
  synthesizer = styled(GtkButton("Synthesizer"), "export-button")
  hbox_main = GtkBox(:h)
  g_main = styled(GtkGrid(), "footer")
  set_gtk_property!(g_main, :row_spacing, 5)
  set_gtk_property!(g_main, :column_spacing, 5)
  set_gtk_property!(g_main, :row_homogeneous, true)
  set_gtk_property!(g_main, :column_homogeneous, true)
  g_main[1, 1] = transcriber
  g_main[2, 1] = synthesizer
  # set_gtk_property!(hbox_main, :spacing, 10)
  push!(vbox_main, image)
  # push!(hbox_main, transcriber)
  # push!(hbox_main, synthesizer)
  push!(vbox_main, g_main)
  push!(win, vbox_main)
  showall(win)

  signal_connect(transcriber, "clicked") do _
    create_transcriber_window()
    Gtk.destroy(win)
  end

  signal_connect(synthesizer, "clicked") do _
    create_synth_window(false)
    Gtk.destroy(win)
  end
end

function create_synth_window(from_transcriber)

  playing = false
  reproduction_speed = 1
  with_duration = true

  header = styled(GtkLabel("Synthesizer"), "header")
  import_button = styled(GtkButton("Import"), "export-button")
  wrap_button = styled(GtkButton("Wrap"), "export-button")
  play_button = styled(GtkButton("Play"), "export-button")
  back_button = styled(GtkButton("Back"), "export-button")
  export_button = styled(GtkButton("Export"), "export-button")
  clear_button = styled(GtkButton("Clear"), "export-button")
  increase_tempo_button = styled(GtkButton("+"), "export-button")
  decrease_tempo_button = styled(GtkButton("-"), "export-button")
  tempo_label = styled(GtkLabel("10"), "tempo-label")
  tablature = styled(GtkGrid(), "grid")
  note_labels = styled(GtkGrid(), "grid")
  sidebar = styled(GtkBox(:v), "sidebar")
  tab_scroll = styled(GtkScrolledWindow(), "scroll-window")
  # history_scroll = styled(GtkScrolledWindow(), "scroll-window")
  # history_list = GtkListStore
  play_tab_button = styled(GtkButton("Play"), "export-button")
  input_tab_buffer = GtkTextBuffer()
  input_tab_area = styled(GtkTextView(input_tab_buffer), "text-view")
  input_tab_vbox = styled(GtkBox(:v), "text-view")
  set_gtk_property!(input_tab_area, :height_request, 180)
  # set_gtk_property!(input_tab_area, :max_content_height, 6)
  with_duration_button = styled(GtkButton("With durations"), "export-button")
  header_grid = styled(GtkGrid(), "grid")
  separator = styled(GtkLabel("                                                      "), "separator")


  notes = ["e", "B", "G", "D", "A", "E"]

  for i in range(1, NUM_ROWS)
    note = styled(GtkLabel(notes[i]), "note")

    for j in range(1, NUM_COLS)
      local entry = styled(GtkEntry(), "input")
      set_gtk_property!(entry, :width_chars, 2)
      set_gtk_property!(entry, :xalign, 0.5)
      set_gtk_property!(entry, :placeholder_text, "-")

      function on_insert_text(ent, text, _, _)

        row, _ = get_index_of(ent, tablature)
        curr_text = get_gtk_property(ent, :text, String)
        allowed_chars = ['0', '1', '2', '3', '4']
        allowed_last = [allowed_chars; ['5', '6', '7', '8', '9']]
        is_allowed = ((row == 1) ?
                      all(c -> c in allowed_last, text) :
                      all(c -> c in allowed_chars, text)) && text != ""

        if (is_allowed)

          # Clear column
          async_set(ent, text) # This has to be run before below sets for some reason?

          for k in range(1, NUM_ROWS)
            if k != i
              temp_ent = tablature[j, k]
              async_set(temp_ent, "")
            end
          end

        else
          # Invalid input
          async_set(ent, curr_text)
        end
      end

      function on_key_press(widget, event)
        row, col = get_index_of(widget, tablature)

        if (event.keyval == 65288) # Delete
          async_set(widget, "")

        elseif (event.keyval == 65361) # Left
          new_col = WRAP ?
                    (
            (col == 2) ?
            NUM_COLS :
            col - 1
          ) : max(1, col - 1)

          Gtk.grab_focus(tablature[new_col, row])

        elseif (event.keyval == 65362) # Up
          new_row = WRAP ? (
            (row == 1) ?
            NUM_ROWS :
            row - 1
          ) : max(1, row - 1)

          Gtk.grab_focus(tablature[col, new_row])

        elseif (event.keyval == 65363) # Right
          new_col = WRAP ? (
            (col == NUM_COLS) ?
            2 :
            col + 1
          ) : min(NUM_COLS, col + 1)
          Gtk.grab_focus(tablature[new_col, row])

        elseif (event.keyval == 65364) # Down
          new_row = WRAP ? (
            (row == NUM_ROWS) ?
            1 :
            row + 1) : min(NUM_ROWS, row + 1)
          Gtk.grab_focus(tablature[col, new_row])

        elseif (event.keyval >= 48 && event.keyval <= 57)
          return false
        end
        return true
      end
      signal_connect(on_insert_text, entry, "insert-text")
      signal_connect(on_key_press, entry, "key-press-event")
      tablature[j, i] = entry
    end

    note_labels[1, i] = note
  end

  for i in range(1, NUM_COLS)
    tempo_button = styled(GtkButton(), "tempo-button")
    set_gtk_property!(tempo_button, :label, "1")
    set_gtk_property!(tempo_button, :xalign, 0.5)
    tablature[i, NUM_ROWS+1] = tempo_button

    function on_click_tempo(_)
      curr_text = get_gtk_property(tempo_button, :label, String)
      curr_tempo = parse(Int, curr_text)
      new_tempo = (curr_tempo % 4) + 1
      set_gtk_property!(tempo_button, :label, string(new_tempo))
    end
    signal_connect(on_click_tempo, tempo_button, "clicked")

  end

  function flip_wrap(_)
    global WRAP = !WRAP
    if WRAP
      set_gtk_property!(wrap_button, :label, "No wrap")
    else
      set_gtk_property!(wrap_button, :label, "Wrap")
    end
  end

  function on_export_button_press(_)
    output = ""
    save_file = save_dialog_native("Save file", GtkNullContainer(), ("*.txt",))
    for i in range(1, NUM_ROWS)
      for j in range(1, NUM_COLS)
        local entry = tablature[j, i]
        text = get_gtk_property(entry, :text, String)
        # text = (text == "") ?
        #        repeat("-", parse(Int, get_gtk_property(tablature[j, NUM_ROWS+1], :label, String))) :
        #        text * repeat("s", parse(Int, get_gtk_property(tablature[j, NUM_ROWS+1], :label, String)) - 1)
        text = (text == "") ? "-" : text
        # text = text * repeat("s", parse(Int, get_gtk_property(tablature[j, NUM_ROWS+1], :label, String)) - 1)
        output = string(output, text)
      end
      output = string(output, "\n")
    end
    for j in range(1, NUM_COLS)
      local entry = tablature[j, NUM_ROWS+1]
      text = get_gtk_property(entry, :label, String)
      output = string(output, text, " ")
    end
    write(save_file, output)
  end

  function on_back_button_press(_)

    if (from_transcriber)
      create_transcriber_window()
      Gtk.destroy(synth_win)
    else
      create_main_window()
      Gtk.destroy(synth_win)
    end
  end

  function on_clear_button_press(_)
    for i in range(1, NUM_ROWS)
      for j in range(1, NUM_COLS)
        entry = tablature[j, i]
        async_set(entry, "")
      end
    end
    for i in range(1, NUM_COLS)
      tempo_button = tablature[i, NUM_ROWS+1]
      set_gtk_property!(tempo_button, :label, "1")
    end
  end

  function on_play_button_press(_)
    output = ""
    for i in range(1, NUM_ROWS)
      for j in range(1, NUM_COLS)
        local entry = tablature[j, i]
        text = get_gtk_property(entry, :text, String)
        # text = (text == "") ?
        #        repeat("-", parse(Int, get_gtk_property(tablature[j, NUM_ROWS+1], :label, String))) :
        #        text * repeat("s", parse(Int, get_gtk_property(tablature[j, NUM_ROWS+1], :label, String)) - 1)
        text = (text == "") ? "-" : text
        # text = text * repeat("s", parse(Int, get_gtk_property(tablature[j, NUM_ROWS+1], :label, String)) - 1)
        output = string(output, text)
      end
      output = string(output, "\n")
    end
    for j in range(1, NUM_COLS)
      local entry = tablature[j, NUM_ROWS+1]
      text = get_gtk_property(entry, :label, String)
      output = string(output, text, " ")
    end

    write(string("output.txt"), output)

    # Threads.@spawn begin
    main_synthesizer_withDurations(string("output.txt"), reproduction_speed)
    # end

  end

  function on_import_button_press(_)
    file = open_dialog_native("Pick a file", GtkNullContainer(), ("*.txt",))
    println(file)
    if file != ""
      lines = readlines(file)
      line_length = length(lines[1])

      last_non_s_col = 1

      for i in range(1, line_length)
        for j in range(1, NUM_ROWS)
          char = lines[j][i]
          if (char != "-")
            entry = tablature[last_non_s_col, j]
            async_set(entry, string(char))
          end
        end
        last_non_s_col = last_non_s_col + 1
      end
      counter = 1
      for i in range(1, stop=length(lines[NUM_ROWS+1]), step=2)
        tempo_button = tablature[counter, NUM_ROWS+1]
        counter = counter + 1
        set_gtk_property!(tempo_button, :label, string(lines[NUM_ROWS+1][i]))
      end
    end
  end

  function on_increase_tempo_button_press(_)
    curr_tempo = get_gtk_property(tempo_label, :label, String)
    new_tempo = min(20, parse(Int, curr_tempo) + 1)
    reproduction_speed = new_tempo
    set_gtk_property!(tempo_label, :label, string(new_tempo))
    if (reproduction_speed >= 4) # Max tempo
      return
    end
  end

  function on_decrease_tempo_button_press(_)
    curr_tempo = get_gtk_property(tempo_label, :label, String)
    new_tempo = max(1, parse(Int, curr_tempo) - 1)
    reproduction_speed = new_tempo
    set_gtk_property!(tempo_label, :label, string(new_tempo))
  end

  is_play_button_visible = false
  function on_enter_text_into_tab(_, event)

    text = get_gtk_property(input_tab_buffer, :text, String)
    if !is_play_button_visible && text != "" #&&
      #  length(split(text, "\n")) == 7
      # push!(hbox, decrease_tempo_button)
      # push!(hbox, tempo_label)
      # push!(hbox, increase_tempo_button)
      push!(input_tab_vbox, play_tab_button)
      showall(synth_win)
      is_play_button_visible = true
    end

    # if length(split(text, "\n")) > 7
    #   set_gtk_property!(input_tab_buffer, :text, join(split(text, "\n")[1:7], "\n"))
    # elseif length(split(text, "\n")) == 7 && event.keyval == 65293
    #   set_gtk_property!(input_tab_buffer, :text, join(split(text, "\n")[1:7], "\n"))
    # end
  end

  function on_click_play_tab_button(_)
    reproduction_speed = parse(Int, get_gtk_property(tempo_label, :label, String))
    text = get_gtk_property(input_tab_buffer, :text, String)
    write("asdf.txt", text)

    if with_duration
      main_synthesizer_withDurations("asdf.txt", reproduction_speed)
    else
      main_synthesizer_noDurations("asdf.txt", reproduction_speed / 10)
    end
  end

  function on_click_with_duration_button(_)
    with_duration = !with_duration
    if with_duration
      set_gtk_property!(with_duration_button, :label, "With durations")
    else
      set_gtk_property!(with_duration_button, :label, "Without durations")
    end
  end


  # Connect signals
  signal_connect(on_click_with_duration_button, with_duration_button, "clicked")
  signal_connect(on_click_play_tab_button, play_tab_button, "clicked")
  signal_connect(on_enter_text_into_tab, input_tab_area, "key-press-event")
  signal_connect(on_increase_tempo_button_press, increase_tempo_button, "clicked")
  signal_connect(on_decrease_tempo_button_press, decrease_tempo_button, "clicked")
  signal_connect(on_import_button_press, import_button, "clicked")
  signal_connect(flip_wrap, wrap_button, "clicked")
  signal_connect(on_export_button_press, export_button, "clicked")
  signal_connect(on_back_button_press, back_button, "clicked")
  signal_connect(on_clear_button_press, clear_button, "clicked")
  signal_connect(on_play_button_press, play_button, "clicked")

  synth_win = GtkWindow("", 400, 400)
  vbox = GtkBox(:v)
  header_box = styled(GtkBox(:h), "header-box")
  buttons_vbox = GtkBox(:v)
  entire_hbox = GtkBox(:h)

  if (from_transcriber)
    file = "guitar_tab_Concise.txt"

    # for i in range(1, NUM_ROWS)
    #   for j in range(1, NUM_COLS)
    #     entry = tablature[j, i]
    #     async_set(entry, "")
    #   end
    # end
    # for i in range(1, NUM_COLS)
    #   tempo_button = tablature[i, NUM_ROWS+1]
    #   set_gtk_property!(tempo_button, :label, "1")
    # end

    if file != ""
      lines = readlines(file)
      line_length = length(lines[1])

      last_non_s_col = 1

      for i in range(1, line_length)
        for j in range(1, NUM_ROWS)
          char = lines[j][i]
          if (char != "-")
            entry = tablature[last_non_s_col, j]
            async_set(entry, string(char))
          end
        end
        last_non_s_col = last_non_s_col + 1
      end
      counter = 1
      for i in range(1, stop=length(lines[NUM_ROWS+1]), step=2)
        tempo_button = tablature[counter, NUM_ROWS+1]
        counter = counter + 1
        set_gtk_property!(tempo_button, :label, string(lines[NUM_ROWS+1][i]))
      end
    end
  end

  set_gtk_property!(tab_scroll, :hscrollbar_policy, Gtk.GtkPolicyType.ALWAYS)
  set_gtk_property!(tab_scroll, :vscrollbar_policy, Gtk.GtkPolicyType.NEVER)
  set_gtk_property!(tab_scroll, :min_content_width, 400)

  set_gtk_property!(tablature, :row_spacing, 5)



  # header_grid[1, 1] = header
  header_grid[1, 1] = back_button
  header_grid[2, 1] = clear_button
  header_grid[3, 1] = wrap_button
  header_grid[4, 1] = decrease_tempo_button
  header_grid[5, 1] = tempo_label
  header_grid[6, 1] = increase_tempo_button

  # push!(header_grid, header)
  # push!(header_box, back_button)
  # push!(header_box, clear_button)
  # push!(header_box, wrap_button)
  # push!(header_box, decrease_tempo_button)
  # push!(header_box, tempo_label)
  # push!(header_box, increase_tempo_button)
  # push!(header_box, spinner)
  push!(header_box, header)
  push!(header_box, header_grid)
  push!(vbox, header_box)
  push!(buttons_vbox, import_button)
  push!(buttons_vbox, export_button)
  push!(buttons_vbox, play_button)
  push!(entire_hbox, buttons_vbox)
  push!(tab_scroll, tablature)
  push!(entire_hbox, note_labels)
  push!(entire_hbox, tab_scroll)
  push!(entire_hbox, sidebar)
  push!(vbox, entire_hbox)
  push!(vbox, separator)
  push!(input_tab_vbox, with_duration_button)
  push!(input_tab_vbox, input_tab_area)
  push!(vbox, input_tab_vbox)
  push!(synth_win, vbox)
  showall(synth_win)
end

function create_transcriber_window()

  # Regular variables
  S = 44100
  N = 1024
  maxtime = 1000
  recording = false
  nsample = 0
  song = Float32[]
  reproduction_speed = 10

  # Layout
  win = GtkWindow("Transcriber", 400, 400)
  vbox = GtkBox(:v)
  hbox = styled(GtkBox(:h), "header-box")
  play_hbox = GtkBox(:h)
  footer = styled(GtkBox(:h), "")
  scroll_view = styled(GtkScrolledWindow(), "scroll-window")
  set_gtk_property!(scroll_view, :hscrollbar_policy, Gtk.GtkPolicyType.ALWAYS)
  set_gtk_property!(scroll_view, :vscrollbar_policy, Gtk.GtkPolicyType.NEVER)
  tab = styled(GtkGrid(), "grid")
  set_gtk_property!(tab, :row_spacing, 5)
  set_gtk_property!(tab, :column_spacing, 5)
  input_tab_vbox = GtkBox(:v)

  # Elements
  header = styled(GtkLabel("Transcriber"), "header")
  back_button = styled(GtkButton("Back"), "export-button")
  import_button = styled(GtkButton("Import"), "export-button")
  timer_label = styled(GtkLabel("0:00"), "timer-label")
  record_button = styled(GtkButton("Record"), "export-button")
  stop_button = styled(GtkButton("Stop"), "export-button")
  play_recorded_button = styled(GtkButton("Play"), "export-button")
  export_button = styled(GtkButton("Transcribe"), "export-button")
  go_to_synth = styled(GtkButton("Synthesizer"), "export-button")
  play_transcribed_button = styled(GtkButton("Play"), "export-button")
  increase_tempo_button = styled(GtkButton("+"), "export-button")
  decrease_tempo_button = styled(GtkButton("-"), "export-button")
  tempo_label = styled(GtkLabel("10"), "header")


  # Functions and Callbacks

  function on_back_button_press(_)
    create_main_window()
    Gtk.destroy(win)
  end

  function on_import_button_press(_)
    input = open_dialog_native("Pick a file", GtkNullContainer(), ("*.wav",))
    main_transcriber(input)

    file = "guitar_tab.txt"
    if file != ""
      lines = readlines(file)
      line_length = length(lines[1])

      for i in range(1, line_length)
        for j in range(1, NUM_ROWS)
          tab[i, j] = styled(GtkLabel(string(lines[j][i])), "input")
        end
      end
      # counter = 1
      # for i in range(1, stop=length(lines[NUM_ROWS+1]), step=2)
      #   tempo_button = tab[counter, NUM_ROWS+1]
      #   counter = counter + 1
      #   set_gtk_property!(tempo_button, :label, string(lines[NUM_ROWS+1][i]))
      # end
      println("Transcribed")
    else
      println("No file selected")
    end

    push!(footer, play_transcribed_button)
    push!(footer, go_to_synth)

    push!(hbox, decrease_tempo_button)
    push!(hbox, tempo_label)
    push!(hbox, increase_tempo_button)

    showall(win)
  end

  function record_loop!(in_stream, buf)
    Niter = floor(Int, maxtime * S / N)
    println("\nRecording up to Niter=$Niter ($maxtime sec).")
    for iter in 1:Niter
      if !recording
        break
      end
      read!(in_stream, buf)
      append!(song, buf) # Append buffer to song
      nsample += N
      print("\riter=$iter/$Niter nsample=$nsample")
    end
  end

  function call_record(w)
    recording = true

    # Threads.@spawn begin
    global nsample = 0 # Count number of samples recorded
    global song = Float32[] # Initialize "song" as an empty array
    set_gtk_property!(timer_label, :label, "0:00")

    delete!(play_hbox, record_button)
    delete!(play_hbox, play_recorded_button)
    delete!(play_hbox, export_button)
    push!(play_hbox, stop_button)
    push!(play_hbox, timer_label)
    showall(win)

    # end
    Threads.@spawn begin
      in_stream = PortAudioStream(1, 0) # Default input device
      buf = read(in_stream, N) # Warm-up
      global song = zeros(Float32, maxtime * S)
      @async record_loop!(in_stream, buf)
    end

    Threads.@spawn begin
      while recording == true
        sleep(1)
        # println("asjdflkajflkasdjfsalkaskjfd")
        curr_time = get_gtk_property(timer_label, :label, String)
        # println(curr_time)
        curr_time = split(curr_time, ":")
        minutes = parse(Int, curr_time[1])
        seconds = parse(Int, curr_time[2])
        seconds += 1
        if seconds == 60
          minutes += 1
          seconds = 0
        end
        new_time = string(minutes, ":", lpad(seconds, 2, "0"))

        Gtk.GLib.g_idle_add() do
          set_gtk_property!(timer_label, :label, new_time)
          showall(win)
          Cint(false)
        end
      end
    end


  end

  function call_stop(w)
    recording = false
    delete!(play_hbox, stop_button)
    push!(play_hbox, record_button)
    push!(play_hbox, play_recorded_button)
    push!(play_hbox, export_button)
    showall(win)
    # new_play_button = make_button("Play", call_play, 3, "wg", "color:white; background:green;")
    # new_export_button = make_button("Export", call_export, 4, "yb", "color:yellow; background:black;")
    # g[3, 1] = new_play_button
    # g[4, 1] = new_export_button

    sleep(0.1) # Ensure the async record loop finished
    duration = round(nsample / S, digits=2)
    flush(stdout)
    println("\nStopped recording at nsample=$nsample, duration $duration seconds.")
    global song = song[1:nsample] # Truncate song to the recorded duration
  end

  function call_play(w)
    # println("Playing recording.")
    @async sound(song, S) # Play the entire recording
  end

  function call_export(w)
    # save_file = save_dialog_native("Save file", GtkNullContainer(), ("*.wav",))

    save_file = "recordedFromComputer.wav"

    if (save_file != "")
      println("Exporting to $save_file")
      wavwrite(song, save_file, Fs=S)
    end

    input = "recordedFromComputer.wav"
    main_transcriber(input)

    file = "guitar_tab.txt"
    if file != ""
      lines = readlines(file)
      line_length = length(lines[1])

      for i in range(1, line_length)
        for j in range(1, NUM_ROWS)
          tab[i, j] = styled(GtkLabel(string(lines[j][i])), "input")
        end
      end
      # counter = 1
      # for i in range(1, stop=length(lines[NUM_ROWS+1]), step=2)
      #   tempo_button = tab[counter, NUM_ROWS+1]
      #   counter = counter + 1
      #   set_gtk_property!(tempo_button, :label, string(lines[NUM_ROWS+1][i]))
      # end
      println("Transcribed")
    else      
      println("No file selected")
    end

    push!(footer, play_transcribed_button)
    push!(footer, go_to_synth)

    push!(hbox, decrease_tempo_button)
    push!(hbox, tempo_label)
    push!(hbox, increase_tempo_button)

    showall(win)
  end

  function on_go_to_synth(_)
    create_synth_window(true)
    Gtk.destroy(win)
  end

  function asyncDo(cols)
    state = MyState(nothing, 0)
    state.task = Task(() -> asyncDoInner(state, cols))
    schedule(state.task)
    return state
  end

  function asyncDoInner(state::MyState, cols)
    for i = 1:(cols*200*(1/reproduction_speed))
      hadj = get_gtk_property(scroll_view, :hadjustment, GtkAdjustment)
      set_gtk_property!(hadj, :value, get_gtk_property(hadj, :value, Float64) + 0.18 * reproduction_speed)
      # print(i)
      state.someCounter = i
      sleep(0.01) # I think the yield suffices
      yield()
    end
  end

  # the following function is the callback that is invoked called by signal_connect
  # function on_button_clicked(w)

  # end

  function on_play_transcribed_button_press(_)
    cols = length(readlines("guitar_tab_Concise.txt")[1])

    @async begin
      main_synthesizer_withDurations("guitar_tab_Concise.txt", reproduction_speed)
    end


    @async begin
      hadj = get_gtk_property(scroll_view, :hadjustment, GtkAdjustment)
      set_gtk_property!(hadj, :value, 0)
      sleep(5 * (1 / reproduction_speed))
      state = asyncDo(cols)
      timer = nothing
      function update(::Timer)
        if Base.istaskfailed(state.task)
          close(timer)
          error("something is wrong")
          return
        end
        # Here the UI should be update. Access state.someCounter to get the progress
        if istaskdone(state.task)
          close(timer)
        end
        return
      end
      timer = Timer(update, 0.0, interval=0.1)
    end

    return
    # print("1")
    # Threads.@spawn begin
    #   for i = 1:100
    #     # print("2")
    #     hadj = get_gtk_property(scroll_view, :hadjustment, GtkAdjustment)
    #     # print("3")
    #     Gtk.GLib.g_idle_add() do
    #       # print("4")
    #       set_gtk_property!(hadj, :value, get_gtk_property(hadj, :value, Float64) + 1)
    #       # print("5")
    #       sleep(0.01)
    #       yield()
    #       Cint(false)
    #     end
    #     # set_gtk_property!(hadj, :value, get_gtk_property(hadj, :value, Float64) + 1)
    #     # sleep(0.01)
    #   end
    # end
  end

  function on_increase_tempo_button_press(_)
    curr_tempo = get_gtk_property(tempo_label, :label, String)
    new_tempo = min(20, parse(Int, curr_tempo) + 1)
    reproduction_speed = new_tempo
    set_gtk_property!(tempo_label, :label, string(new_tempo))
    if (reproduction_speed >= 4) # Max tempo
      return
    end
  end

  function on_decrease_tempo_button_press(_)
    curr_tempo = get_gtk_property(tempo_label, :label, String)
    new_tempo = max(1, parse(Int, curr_tempo) - 1)
    reproduction_speed = new_tempo
    set_gtk_property!(tempo_label, :label, string(new_tempo))
  end

  signal_connect(on_increase_tempo_button_press, increase_tempo_button, "clicked")
  signal_connect(on_decrease_tempo_button_press, decrease_tempo_button, "clicked")
  signal_connect(call_record, record_button, "clicked")
  signal_connect(call_stop, stop_button, "clicked")
  signal_connect(call_play, play_recorded_button, "clicked")
  signal_connect(call_export, export_button, "clicked")
  signal_connect(on_import_button_press, import_button, "clicked")
  signal_connect(on_back_button_press, back_button, "clicked")
  signal_connect(on_go_to_synth, go_to_synth, "clicked")
  signal_connect(on_play_transcribed_button_press, play_transcribed_button, "clicked")


  # Add to layout
  push!(play_hbox, record_button)
  push!(hbox, header)
  push!(hbox, back_button)
  push!(hbox, import_button)
  # push!(input_tab_vbox, input_tab_area)
  push!(vbox, hbox)
  # push!(vbox, input_tab_vbox)
  push!(vbox, play_hbox)
  push!(scroll_view, tab)
  push!(vbox, scroll_view)
  push!(vbox, footer)
  push!(win, vbox)

  showall(win)
end


create_main_window()