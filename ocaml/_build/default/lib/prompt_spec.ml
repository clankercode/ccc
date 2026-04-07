exception Empty_prompt

let build_prompt_spec prompt =
  let trimmed = String.trim prompt in
  if trimmed = "" then raise Empty_prompt
  else Command_spec.make ["opencode"; "run"; trimmed]
