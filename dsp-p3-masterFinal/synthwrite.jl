using WAV
# using Plots
using MAT
using Sound
using FFTW
# plotlyjs()

function adsr_envelope(t, attack_time, decay_time, sustain_level, release_time, total_duration)
  sustain_decay_rate = 3.5  # Hardcoded decay rate for the sustain phase

  if t < attack_time
    # Attack phase: linear increase from 0 to 1
    return t / attack_time
  elseif t < attack_time + decay_time
    # Decay phase: linear decrease from 1 to sustain_level
    return 1 - (1 - sustain_level) * (t - attack_time) / decay_time
  elseif t < total_duration - release_time
    # Sustain phase: exponential decay starting at sustain_level
    sustain_time = t - attack_time - decay_time
    return sustain_level * exp(-sustain_decay_rate * sustain_time)
  else
    # Release phase: linear decrease from current sustain level to 0
    remaining_time = t - (total_duration - release_time)
    current_sustain = sustain_level * exp(-sustain_decay_rate * (total_duration - attack_time - decay_time - release_time))
    return current_sustain * (1 - remaining_time / release_time)
  end
end
function npos2freq(npos)
  return 83.24 * 2^(npos / 12)
end
function play_npos(song) #song is ((npos, duration),(..,...),(..,..))
  played_song = Float64[]
  envelopes_list = [
    (0.02, 0.09, 0.614, 0.14),
    (0.03, 0.13, 0.32, 0.21),
    (0.05, 0.18, 0.71, 0.13),
    (0.03, 0.11, 0.56, 0.13),
    (0.04, 0.07, 0.56, 0.14),
    (0.035, 0.137, 0.31, 0.3)
  ] #(attack time, decay time, sustain level, release time) [6] is 6th string
  amplitudes_list = [
    [0.72, 0.82, 0.95, 1.00, 0.756, 0.46, 0.19, 0.12, 0.149, 0.0657, 0.056, 0.091],
    [1.0, 0.3, 0.175, 0.127, 0.029, 0.101, 0.067, 0.22, 0.087, 0.035, 0.036, 0.017],
    [1.0, 0.96, 0.42, 0.33, 0.09, 0.018, 0.12, 0.06, 0.058, 0.022, 0.006, 0.018],
    [1.0, 0.9, 0.41, 0.42, 0.15, 0.23, 0.21, 0.06, 0.16, 0.06, 0.03, 0.05],
    [0.345, 1.0, 0.19, 0.39, 0.007, 0.05, 0.047, 0.057, 0.053, 0.03, 0.03, 0.036],
    [0.24, 0.9, 0.63, 1.0, 0.44, 0.06, 0.08, 0.07, 0.05, 0.09, 0.03, 0.035]
  ] #just the amplitudes for each harmonic from fundamental to 11th harmonic  and [6] is 6ht string

  a = 6 #the one for the 6th is the best, really.

  for note in song
    npos, duration = note
    S = 44100
    N = round(Int, duration * S)
    x = zeros(N)
    # Select amplitudes and envelope based on npos
    if npos in 0:4
      # amplitudes = amplitudes_list[6]
      # envelope = envelopes_list[6]

      amplitudes = amplitudes_list[a]
      envelope = envelopes_list[a]
    elseif npos in 5:9
      # amplitudes = amplitudes_list[5]
      # envelope = envelopes_list[5]

      amplitudes = amplitudes_list[a]
      envelope = envelopes_list[a]
    elseif npos in 10:14
      # amplitudes = amplitudes_list[4]
      # envelope = envelopes_list[4]

      amplitudes = amplitudes_list[a]
      envelope = envelopes_list[a]
    elseif npos in 15:18
      # amplitudes = amplitudes_list[3]
      # envelope = envelopes_list[3]

      amplitudes = amplitudes_list[a]
      envelope = envelopes_list[a]
    elseif npos in 19:23
      # amplitudes = amplitudes_list[2]
      # envelope = envelopes_list[2]

      amplitudes = amplitudes_list[a]
      envelope = envelopes_list[a]
    elseif npos in 24:33
      # amplitudes = amplitudes_list[1]
      # envelope = envelopes_list[1]

      amplitudes = amplitudes_list[a]
      envelope = envelopes_list[a]
    else
      # Default case, if needed
      amplitudes = amplitudes_list[6]  # or some default value
      envelope = envelopes_list[6]  # or some default value
    end
    fundamental = npos2freq(npos)
    harmonics = 1:12
    for (n, amplitude) in zip(harmonics, amplitudes)
      freq = fundamental * n
      x += amplitude * cos.(2 * pi * freq * (1:N) / S)
      # println("Harmonic $n: Frequency = $freq Hz, Amplitude = $amplitude")
    end
    for i in 1:length(x)
      t = i / S
      x[i] = adsr_envelope(t, envelope..., duration) * x[i]
    end
    played_song = vcat(played_song, x)
    # sound(2 .* result,S)
  end
  return played_song
end

function parse_guitar_tab_by_columns_withDurations(tab::String)
  lines = split(strip(tab), '\n')
  if length(lines) < 7
    error("Not enough lines for a complete tab and duration information.")
  end

  note_lines = lines[1:end-1]
  duration_line = split(lines[end], ' ')
  durations = parse.(Float64, duration_line)  # Convert each string to Float64

  # Base positions for each string from e to E (from the highest to lowest pitch)
  base_positions = [24, 19, 15, 10, 5, 0]  # Adjusted as per your specification for e, B, G, D, A, E

  # Find the maximum length of the note lines to define the column loop range
  max_length = maximum(length.(note_lines))

  songs = []
  current_duration_idx = 1  # Index for accessing durations

  # Iterate over each column index
  for col_idx in 1:max_length
    if current_duration_idx > length(durations)
      break  # Avoid going out of bounds of the durations array
    end

    for (string_idx, line) in enumerate(note_lines)
      if col_idx <= length(line) && line[col_idx] != '-' && line[col_idx] != ' '
        fret = parse(Int, line[col_idx])  # Fret number
        base_pos = base_positions[string_idx]
        npos = base_pos + fret  # Calculate note position
        duration = durations[current_duration_idx]
        push!(songs, (npos, duration))
      end
    end
    # Move to the next duration after processing a full column
    current_duration_idx += 1
  end
  return songs
end
function read_and_parse_tab_withDurations(filename::String)
  # Read the entire file content
  content = read(filename, String)
  # Use the parsing function previously discussed
  return parse_guitar_tab_by_columns_withDurations(content)
end

function parse_guitar_tab_by_columns_noDurations(tab::String)
  lines = split(strip(tab), '\n')

  if length(lines) != 6
    error("Incorrect number of lines for a standard guitar tab without durations.")
  end

  # Base positions for each string from e to E (from the highest to lowest pitch)
  base_positions = [24, 19, 15, 10, 5, 0]

  # Define the default duration for each note
  default_duration = 0.35  # Standard duration if no durations are provided

  songs = []

  # Find the maximum length of the note lines to define the column loop range
  max_length = maximum(length.(lines))

  # Iterate over each column index
  for col_idx in 1:max_length
    for (string_idx, line) in enumerate(lines)
      if col_idx <= length(line) && line[col_idx] != '-' && line[col_idx] != ' '
        fret = parse(Int, line[col_idx])  # Fret number
        base_pos = base_positions[string_idx]
        npos = base_pos + fret  # Calculate note position
        push!(songs, (npos, default_duration))
      end
    end
  end
  return songs
end
function read_and_parse_tab_noDurations(filename::String)
  # Read the entire file content
  content = read(filename, String)
  # Use the parsing function previously discussed
  return parse_guitar_tab_by_columns_noDurations(content)
end

function convert_to_tuple_of_tuples(note_list::Array)
  # Convert the array of tuples into a tuple of tuples
  return tuple(note_list...)
end
function scale_durations(notes, scale_factor)
  # Handling a tuple of tuples directly
  new_notes = []
  for i in 1:length(notes)
    tuple = (notes[i][1], notes[i][2] * scale_factor)
    push!(new_notes, tuple)
  end
  return convert_to_tuple_of_tuples(new_notes)
end

function main_synthesizer_withDurations(textTabName, speed_factor)
  # #will read the .txt and give us the tupples in [(.,.),(.,.)]
  song_list = read_and_parse_tab_withDurations(textTabName)
  # println(song_list)
  song_tuples = convert_to_tuple_of_tuples(song_list)
  # println("Converted tuple of tuples: ",song_tuples)
  # c=2
  # println(scale_durations(song_tuples,c))

  S = 44100 #default
  c = 1 / speed_factor
  final_song_tuples = scale_durations(song_tuples, c)
  x_2 = play_npos(final_song_tuples)

  Threads.@spawn try
    sound(x_2, S)
  catch e
    println("Error during sound playback: ", e)
  end

  # wavwrite(testAllNotes, "synthFromComputer.wav", Fs=S)
end

function main_synthesizer_noDurations(textTabName, speed_factor)
  # #will read the .txt and give us the tupples in [(.,.),(.,.)]
  song_list = read_and_parse_tab_noDurations(textTabName)
  # println(song_list)
  song_tuples = convert_to_tuple_of_tuples(song_list)
  # println("Converted tuple of tuples: ",song_tuples)
  # c=2
  # println(scale_durations(song_tuples,c))

  S = 44100 #default
  c = 1 / speed_factor
  final_song_tuples = scale_durations(song_tuples, c)
  x_2 = play_npos(final_song_tuples)
  sound(x_2, S)
  # wavwrite(testAllNotes, "synthFromComputer.wav", Fs=S)
end

# reproduction_speed = 0.64
# main_synthesizer_withDurations("guitar_tab_Concise.txt", reproduction_speed) #for the w/ durations option
# main_synthesizer_noDurations("guitar_tab_Concise.txt",reproduction_speed) #for the w/o durations option