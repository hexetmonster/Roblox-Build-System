--!strict
-- == normal users plz ignore == --
local _Types = {}

export type Action = {
	action:"Place" | "Remove",
	instance:Instance,
}

export type PlayerHistory = {
	stack:{Action},
	pointer:number,
}

export type BuildServer = {
	PlayerHistory:{[Player]:PlayerHistory},
	Place:(self:BuildServer, player:Player, objectName:any, cf:any, scaleOrSize:any, connectedTargets:any, requestedMode:any) -> boolean,
	Remove:(self:BuildServer, player:Player, target:any) -> boolean,
	Undo:(self:BuildServer, player:Player) -> boolean,
	Redo:(self:BuildServer, player:Player) -> boolean,
}

export type BuildClient = {
	Player:Player,
	GhostModel:Model?,
	HitboxVisual:SelectionBox?,
	IsRemoving:boolean,
	CanPlace:boolean,
	CurrentRotation:number,
	CurrentScale:number,
	_renderConnection:RBXScriptConnection?,
	PointA:Vector3?,
	CurrentPoint:Vector3?,
	CurrentSnapTarget:Instance?,
	PointASnapTarget:Instance?,
	PlacementMode:string,
	OriginalSize:Vector3?,
	Hook:(self:BuildClient, targetObject:Instance, mode:string?) -> (),
	BindInputs:(self:BuildClient) -> (),
	Place:(self:BuildClient, input:InputObject) -> (),
	Move:(self:BuildClient) -> (),
	Rotate:(self:BuildClient, direction:number) -> (),
	Scale:(self:BuildClient, direction:number) -> (),
	TryRemove:(self:BuildClient) -> (),
	Unhook:(self:BuildClient) -> (),
	Undo:(self:BuildClient) -> (),
	Redo:(self:BuildClient) -> (),
	Remove:(self:BuildClient) -> (),
}

return _Types
