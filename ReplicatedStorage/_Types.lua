--!strict
-- == ignore == --
local _Types = {}
export type Action = {action:string, instance:Instance}
export type BuildServer = typeof(setmetatable({} :: {PlayerHistory:{[Player]:{stack:{Action}, pointer:number}}}, BuildServer))
export type BuildClient = typeof(setmetatable({} :: {Player:Player, GhostModel:Model?, HitboxVisual:SelectionBox?, IsRemoving:boolean, CurrentRotation:number, CurrentScale:number, _renderConnection:RBXScriptConnection?, PointA:Vector3?, PlacementMode:string, OriginalSize:Vector3?}, BuildClient))
return _Types
