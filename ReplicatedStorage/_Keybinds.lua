--!strict
return {
	Place = Enum.UserInputType.MouseButton1; 										                    -- Place()
	PlaceMultiple = {Enum.UserInputType.MouseButton1, Enum.KeyCode.LeftShift}; 	  	-- Place()
	RotateCW = Enum.KeyCode.E; 													                          	-- Rotate()
	RotateCCW = Enum.KeyCode.Q; 													                          -- Rotate()
	ScaleIncrease = Enum.KeyCode.RightBracket; 										                  -- Scale()
	ScaleDecrease = Enum.KeyCode.LeftBracket; 										                  -- Scale()
	Undo = {Enum.KeyCode.LeftControl, Enum.KeyCode.Z}; 								              -- Undo()
	Redo = {Enum.KeyCode.LeftControl, Enum.KeyCode.Y};								              -- Redo()
	Sledgehammer = Enum.KeyCode.K; 													                        -- Remove()
	NoSnap = Enum.KeyCode.LeftAlt;													                        -- Move()
	Cancel = Enum.KeyCode.Z;														                            -- Remove()
}
