(module
  (func (export "loop") (param i32) (result i32) (local i32)
    i32.const 0
    local.set 1
    (loop 
      (block
        local.get 0
        i32.const 0
        i32.eq 
        br_if 0
        local.get 0
        local.get 1
        i32.add
        local.set 1
        local.get 0
        i32.const 1
        i32.sub
        local.set 0
        br 1
      )
    )
    local.get 1
    return
  )
)