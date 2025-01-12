using WAV
using FFTW
using Plots
using MAT
# plotlyjs()
# using Pkg
# Pkg.add(PackageSpec(name="Kaleido_jll", version="0.1"))

function envelope(x; w::Int=501)
  h = (w - 1) ÷ 2 #sliding half-window (default 250 for the w=501)
  x = abs.(x)
  avg(v) = sum(v) / length(v)
  return [avg(x[max(n - h, 1):min(n + h, end)]) for n in 1:length(x)]
end
function find_durations(envelope, threshold::Float64=0.10)
  durations = []
  note_attack_time = -1
  note_release_time = -1

  skip = -1

  for t in 1:length(envelope)
    if t >= skip
      signal_val = envelope[t]
      if signal_val > threshold && note_attack_time == -1
        note_attack_time = t
      elseif signal_val < threshold && note_attack_time != -1
        note_release_time = t #remember that all these are in index dimension, not time.
        push!(durations, (note_release_time - note_attack_time, note_attack_time, note_release_time))
        note_attack_time = -1 #so notes will note dettect any release time after the true end
        skip = t + 3500 #adjust as needed
      end
    end
  end
  return durations
end
function hps_note2fundamental(note, S)
  X = fft(note)
  N = length(note)
  c = 9 #more than this does not work.
  M = min(N ÷ c, length(X))  # using FIVE copies for the HPS, IT WORKS
  X_mag = abs.(X)

  hps = X_mag[1:M]
  for r in 2:c
    hps .*= X_mag[1:r:r*M]
  end

  hps ./= maximum(hps)  # Normalize the HPS

  max_index = argmax(hps)
  f = (max_index - 1) * S / N  # Calculate fundamental frequency
  return f
end
function make_freqs()
  freqs = []
  f0 = 82.41
  for n in 0:33
    freq = f0 * 2^(n / 12)
    push!(freqs, freq)
  end
  return freqs
end
function find_closestGuitarFreq(freq, freqs_vec)
  possible = freqs_vec
  min_dist = 1000
  closest_freq = -1
  for i in 1:length(possible)
    dist = abs(freq - possible[i])
    if dist < min_dist
      closest_freq = possible[i]
      min_dist = dist
    end
  end
  return closest_freq
end
function freq2npos(freq)
  return round(Int, 12 * log2(freq / 82.41))
end
function wav2tuples(file)
  x, S = wavread(file)
  w = 501
  env = envelope(x; w)
  env /= maximum(env)
  threshold = 0.10 #check the values for this one that work
  durations = find_durations(env, threshold)

  freqs = make_freqs()
  song_array = []
  for i in 1:length(durations)
    note = x[durations[i][2]:durations[i][3]]
    f = hps_note2fundamental(note, S)
    closest_f = find_closestGuitarFreq(f, freqs)
    npos = freq2npos(closest_f)
    push!(song_array, [npos, durations[i][1], durations[i][2]]) #npos, duration, attack-time
    # println("($npos, $(durations[i][1]), $(durations[i][2])) \n")
    # println("$(npos)")
  end
  return song_array, S
end

function pusher(S, n, E, A, D, G, B, e, dur_vec, dur)
  # Concatenate strings instead of pushing to arrays
  E *= string(n) * " "
  A *= "-  "
  D *= "-  "
  G *= "-  "
  B *= "-  "
  e *= "-  "
  dur_vec *= string(round(Int, 10 * round(dur / S; digits=1))) * "  " #will have the duration
  return E, A, D, G, B, e, dur_vec
end
function pusher_concise(S, n, E, A, D, G, B, e, dur_vec, dur)
  # Concatenate strings instead of pushing to arrays
  E *= string(n)
  A *= "-"
  D *= "-"
  G *= "-"
  B *= "-"
  e *= "-"
  dur_vec *= string(round(Int, 10 * round(dur / S; digits=1))) * " "
  return E, A, D, G, B, e, dur_vec
end

function build_tab_concise(song_array, S)
  dur_vec, e, B, G, D, A, E = "", "", "", "", "", "", ""
  for i in 1:length(song_array)
    npos = song_array[i][1]
    dur = song_array[i][2]
    if npos in 0:4
      # E, A, D, G, B, e = pusher(60+npos, E, A, D, G, B, e)
      E, A, D, G, B, e, dur_vec = pusher_concise(S, npos, E, A, D, G, B, e, dur_vec, dur)
    elseif npos in 5:9
      # A, E, D, G, B, e = pusher(50+(npos - 5), A, E, D, G, B, e)
      A, E, D, G, B, e, dur_vec = pusher_concise(S, (npos - 5), A, E, D, G, B, e, dur_vec, dur)
    elseif npos in 10:14
      # D, E, A, G, B, e = pusher(40+(npos - 10), D, E, A, G, B, e)
      D, E, A, G, B, e, dur_vec = pusher_concise(S, (npos - 10), D, E, A, G, B, e, dur_vec, dur)
    elseif npos in 15:18
      # G, E, A, D, B, e = pusher(30+(npos - 15), G, E, A, D, B, e)
      G, E, A, D, B, e, dur_vec = pusher_concise(S, (npos - 15), G, E, A, D, B, e, dur_vec, dur)
    elseif npos in 19:23
      # B, E, A, D, G, e = pusher(20+(npos - 19), B, E, A, D, G, e)
      B, E, A, D, G, e, dur_vec = pusher_concise(S, (npos - 19), B, E, A, D, G, e, dur_vec, dur)
    elseif npos in 24:33
      # e, E, A, D, G, B = pusher(10+(npos - 24), e, E, A, D, G, B)
      e, E, A, D, G, B, dur_vec = pusher_concise(S, (npos - 24), e, E, A, D, G, B, dur_vec, dur)
    else
      E, A, D, G, B, e, dur_vec = pusher_concise(S, 'X', E, A, D, G, B, e, dur_vec, dur)
    end
  end
  tab_matrix = [e, B, G, D, A, E, dur_vec]
  return tab_matrix  # Now tab_matrix is an array of strings
end

function build_tab(song_array, S)
  dur_vec, e, B, G, D, A, E = "    ", "e|  ", "B|  ", "G|  ", "D|  ", "A|  ", "E|  "
  for i in 1:length(song_array)
    npos = song_array[i][1]
    dur = song_array[i][2]
    if npos in 0:4
      E, A, D, G, B, e, dur_vec = pusher(S, 60 + npos, E, A, D, G, B, e, dur_vec, dur)
    elseif npos in 5:9
      A, E, D, G, B, e, dur_vec = pusher(S, 50 + (npos - 5), A, E, D, G, B, e, dur_vec, dur)
    elseif npos in 10:14
      D, E, A, G, B, e, dur_vec = pusher(S, 40 + (npos - 10), D, E, A, G, B, e, dur_vec, dur)
    elseif npos in 15:18
      G, E, A, D, B, e, dur_vec = pusher(S, 30 + (npos - 15), G, E, A, D, B, e, dur_vec, dur)
    elseif npos in 19:23
      B, E, A, D, G, e, dur_vec = pusher(S, 20 + (npos - 19), B, E, A, D, G, e, dur_vec, dur)
    elseif npos in 24:33
      e, E, A, D, G, B, dur_vec = pusher(S, 10 + (npos - 24), e, E, A, D, G, B, dur_vec, dur)
    else
      E, A, D, G, B, e, dur_vec = pusher(S, 'X', E, A, D, G, B, e, dur_vec, dur)
    end
  end
  tab_matrix = [e, B, G, D, A, E, dur_vec]
  return tab_matrix  # Now tab_matrix is an array of strings
end

function main_transcriber(file)
  song_array, S = wav2tuples(file)
  tab_result = build_tab(song_array, S)
  tab_result_concise = build_tab_concise(song_array, S)

  # Specify the filename
  filename = "guitar_tab.txt"
  filename_concise = "guitar_tab_Concise.txt"

  # Open the file in write mode and write the result
  open(filename, "w") do file
    for line in tab_result
      write(file, line * "\n")  # Add newline to separate lines of tablature
    end
  end

  open(filename_concise, "w") do file
    for line in tab_result_concise
      write(file, line * "\n")  # Add newline to separate lines of tablature
    end
  end

  # println("Saved guitar tab to $filename")
end
# main_transcriber("60 50 40 30 20 10.wav")
# main_transcriber("Cartolinha.wav")
# main_transcriber("guitarSampleForTest.wav")
# main_transcriber("guitarFromComputer.wav")
# main_transcriber("Bam bam bam baaaan.wav")
