local P,TS,RS,UIS,TP,LI,VU = game:GetService("Players"),game:GetService("TweenService"),game:GetService("RunService"),game:GetService("UserInputService"),game:GetService("TeleportService"),game:GetService("Lighting"),game:GetService("VirtualUser")
local plr = P.LocalPlayer
local MAP = {}
for _,n in ipairs({"Bank 2","Bio Lab","Factory","Hospital 3","Hotel 2","House 2","Mansion 2","Mil Base","Office 3","Police Station","Research Facility","Workspace"}) do MAP[n]=true end
local GOAL,MAXS = 50,25

-- defaults (these carry over after every auto-hop)
local CONFIG = {mode="Tween",speed=25,hop=true,perf=false,off3d=false,afk=true,fling=false,autostart=true}
local S = {on=false,count=0,status="Idle",map="-",coins=0}
for k,v in pairs(CONFIG) do S[k]=v end
local run,tween,render = 0

---------------------------------------------------------------- farming
local cont
local function find()
	if cont and cont:IsDescendantOf(workspace) then return cont end
	cont = nil
	for _,i in ipairs(workspace:GetDescendants()) do
		if MAP[i.Name] then
			local c = i:FindFirstChild("CoinContainer",true)
			if c then cont=c S.map=i.Name return c end
		end
	end
	cont = workspace:FindFirstChild("CoinContainer",true)
	if cont then S.map=cont.Parent.Name end
	return cont
end

local function partOf(k)
	return k:IsA("BasePart") and k or (k:IsA("Model") and k.PrimaryPart) or k:FindFirstChildWhichIsA("BasePart",true)
end

local function status(t) S.status=t render() end

local function hop()
	S.on=false run+=1 status("Joining new server...")
	local d={resume=true}
	for k in pairs(CONFIG) do d[k]=S[k] end
	if not pcall(TP.Teleport,TP,game.PlaceId,plr,d) then status("Hop failed") end
end
TP.TeleportInitFailed:Connect(function() status("Hop failed") end)

local function farm(tok)
	local skip = {}
	local function ok() return S.on and run==tok end
	while ok() do
		if S.hop and S.count>=GOAL then return hop() end
		local ch = plr.Character
		local r = ch and ch:FindFirstChild("HumanoidRootPart")
		local h = ch and ch:FindFirstChildOfClass("Humanoid")
		if not (r and h and h.Health>0) then task.wait(.5) continue end
		local c = find()
		if not c then status("Looking for map...") task.wait(1) continue end

		local coin,part,bd,n = nil,nil,math.huge,0
		for _,k in ipairs(c:GetDescendants()) do
			if k.Name=="Coin_Server" then
				n+=1
				local p = not skip[k] and partOf(k)
				if p then
					local d=(p.Position-r.Position).Magnitude
					if d<bd then coin,part,bd=k,p,d end
				end
			end
		end
		S.coins=n
		if not coin then table.clear(skip) status("Waiting for coins...") task.wait(.5) continue end
		skip[coin]=true

		status("Moving to coin")
		local pos=part.Position
		if S.mode=="Teleport" then
			r.CFrame=CFrame.new(pos)
		else
			tween=TS:Create(r,TweenInfo.new(math.max((pos-r.Position).Magnitude/S.speed,.05),Enum.EasingStyle.Linear),{CFrame=CFrame.new(pos)})
			local cn=coin.AncestryChanged:Connect(function() if not coin:IsDescendantOf(workspace) and tween then tween:Cancel() end end)
			tween:Play() tween.Completed:Wait() tween=nil cn:Disconnect()
		end

local got = false

for a=1,3 do
    if not ok() then break end

    got = not coin:IsDescendantOf(workspace)
    if got then break end

    status("Collecting coin")
    task.wait(0.15)

    got = not coin:IsDescendantOf(workspace)
    if got then break end
end

if got then
    S.count += 1
    render()
end

task.wait(0.05)
	end
end

local function stop() S.on=false run+=1 if tween then tween:Cancel() end status("Stopped") end
local function start()
	if S.on then return end
	S.on=true run+=1
	local t=run
	status("Starting...")
	task.spawn(function() farm(t) if run==t then S.on=false status("Stopped") end end)
end

---------------------------------------------------------------- performance mode
local FX={ParticleEmitter=1,Trail=1,Beam=1,Fire=1,Smoke=1,Sparkles=1,BlurEffect=1,BloomEffect=1,SunRaysEffect=1,DepthOfFieldEffect=1,ColorCorrectionEffect=1}
local sv,pc,pq,ps = {}
local function strip(i)
	pcall(function()
		local c=i.ClassName
		if FX[c] then if i.Enabled then sv[i]={"e"} i.Enabled=false end
		elseif c=="Decal" or c=="Texture" then sv[i]=sv[i] or {"t",i.Transparency} i.Transparency=1
		elseif i:IsA("BasePart") and c~="Terrain" then sv[i]=sv[i] or {"p",i.Material,i.Reflectance,i.CastShadow} i.Material=Enum.Material.SmoothPlastic i.Reflectance=0 i.CastShadow=false end
	end)
end
local function perf(on)
	if on then
		pcall(function() pq=settings().Rendering.QualityLevel settings().Rendering.QualityLevel=Enum.QualityLevel.Level01 end)
		ps=LI.GlobalShadows LI.GlobalShadows=false
		pc={workspace.DescendantAdded:Connect(strip),LI.DescendantAdded:Connect(strip)}
		task.spawn(function()
			for i,d in ipairs(workspace:GetDescendants()) do strip(d) if i%250==0 then task.wait() end end
			for _,d in ipairs(LI:GetDescendants()) do strip(d) end
		end)
	else
		for _,c in ipairs(pc or {}) do c:Disconnect() end
		for i,d in pairs(sv) do pcall(function()
			if d[1]=="e" then i.Enabled=true elseif d[1]=="t" then i.Transparency=d[2] else i.Material,i.Reflectance,i.CastShadow=d[2],d[3],d[4] end
		end) end
		sv={}
		pcall(function() LI.GlobalShadows=ps settings().Rendering.QualityLevel=pq end)
	end
end

---------------------------------------------------------------- anti-afk / anti-fling
plr.Idled:Connect(function() if S.afk then VU:CaptureController() VU:ClickButton2(Vector2.new()) end end)
local fc={}
local function antifling(on)
	for _,c in ipairs(fc) do c:Disconnect() end
	fc={}
	if not on then return end
	local safe
	fc[1]=RS.Stepped:Connect(function()
		for _,o in ipairs(P:GetPlayers()) do
			if o~=plr and o.Character then for _,p in ipairs(o.Character:GetChildren()) do if p:IsA("BasePart") then p.CanCollide=false end end end
		end
	end)
	fc[2]=RS.Heartbeat:Connect(function()
		local r=plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
		if not r or S.on then safe=nil return end
		local v=r.AssemblyLinearVelocity
		if Vector3.new(v.X,0,v.Z).Magnitude>60 or r.AssemblyAngularVelocity.Magnitude>20 then
			r.AssemblyLinearVelocity=Vector3.zero r.AssemblyAngularVelocity=Vector3.zero
			if safe then r.CFrame=safe end
		else safe=r.CFrame end
	end)
end

---------------------------------------------------------------- UI
local WHT,GREY,BLUE=Color3.new(1,1,1),Color3.fromRGB(112,112,112),Color3.fromRGB(91,140,238)
local CY={Color3.fromRGB(0,255,255),Color3.fromRGB(0,150,170)}
local RD={Color3.fromRGB(255,90,90),Color3.fromRGB(150,25,45)}
local BAR=Color3.fromRGB(30,30,36)
local function N(c,p,par) local i=Instance.new(c) for k,v in pairs(p) do i[k]=v end i.Parent=par return i end
local function L(par,p) p.BackgroundTransparency=1 p.Font=Enum.Font.SourceSansBold p.TextColor3=WHT p.TextStrokeTransparency=0 p.TextSize=p.TextSize or 16 return N("TextLabel",p,par) end
local function R(p,r) N("UICorner",{CornerRadius=UDim.new(0,r or 4)},p) end
local function K(p,t) N("UIStroke",{Thickness=t,ApplyStrokeMode=Enum.ApplyStrokeMode.Border},p) end

local pg=plr:WaitForChild("PlayerGui")
local old=pg:FindFirstChild("CoinFarmUI") if old then old:Destroy() end
local gui=N("ScreenGui",{Name="CoinFarmUI",ResetOnSpawn=false,IgnoreGuiInset=true,DisplayOrder=50},pg)
local W,H=520,340
local panel=N("Frame",{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(W,H),BackgroundColor3=Color3.fromRGB(18,18,22),BorderSizePixel=0,ClipsDescendants=true},gui)
R(panel,8) K(panel,2)
local sc=N("UIScale",{},panel)
local open=true
local function fit()
	local v=workspace.CurrentCamera.ViewportSize
	local s=math.clamp(math.min((v.Y-24)/H,(v.X-16)/W,1),.4,1)
	if open then sc.Scale=s end
	return s
end
fit()
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)

local top=N("Frame",{Size=UDim2.new(1,0,0,72),BackgroundColor3=BAR,BorderSizePixel=0},panel)
N("Frame",{AnchorPoint=Vector2.new(0,1),Position=UDim2.fromScale(0,1),Size=UDim2.new(1,0,0,2),BackgroundColor3=BLUE,BorderSizePixel=0},top)
local title=L(top,{AnchorPoint=Vector2.new(1,.5),Position=UDim2.new(1,-58,.5,0),Size=UDim2.fromOffset(170,30),Text="COIN FARM",TextSize=28,TextXAlignment=Enum.TextXAlignment.Right})
N("UIGradient",{Color=ColorSequence.new(CY[1],BLUE)},title)
local bottom=N("Frame",{AnchorPoint=Vector2.new(0,1),Position=UDim2.fromScale(0,1),Size=UDim2.new(1,0,0,30),BackgroundColor3=BAR,BorderSizePixel=0},panel)
local stat=L(bottom,{Position=UDim2.fromOffset(10,0),Size=UDim2.new(1,-20,1,0),TextXAlignment=Enum.TextXAlignment.Left,TextSize=15})

local function tg(k,name) return {name=name,text=function() return S[k] and "ON" or "OFF" end,on=function() return S[k] end,click=function() S[k]=not S[k] end} end
local TABS={
	{"Farm","🪙",{
		{name="Auto Farm",red=true,text=function() return S.on and "ON" or "OFF" end,on=function() return S.on end,click=function() if S.on then stop() else start() end end},
		{name="Mode",text=function() return S.mode end,on=function() return true end,click=function() S.mode=S.mode=="Tween" and "Teleport" or "Tween" end},
		{name="Speed (max 25)",text=function() return S.speed end,on=function() return S.mode=="Tween" end,click=function() S.speed=S.speed>=MAXS and 5 or S.speed+5 end},
		{name="Reset Coins",text=function() return S.count.."/"..GOAL end,on=function() return S.count>0 end,click=function() S.count=0 end},
	}},
	{"Server","🌐",{
		tg("hop","Auto-Hop at 50"),tg("autostart","Auto-Start"),
		{name="Hop Now",text=function() return "GO" end,on=function() return true end,click=hop},
	}},
	{"Misc","⚙️",{tg("perf","Performance"),tg("off3d","Render Off"),tg("afk","Anti-AFK"),tg("fling","Anti-Fling")}},
}

local items,tabs,pages={},{},{}
local function pick(n) for k,b in pairs(tabs) do pages[k].Visible=k==n b.BackgroundColor3=k==n and BLUE or GREY end end

for ti,t in ipairs(TABS) do
	local name=t[1]
	local b=N("TextButton",{Position=UDim2.fromOffset(6+(ti-1)*96,6),Size=UDim2.fromOffset(90,60),BackgroundColor3=GREY,Text="",AutoButtonColor=false,BorderSizePixel=0},top)
	R(b,4) K(b,1)
	L(b,{Position=UDim2.fromOffset(0,2),Size=UDim2.new(1,0,0,34),Text=t[2],TextSize=26})
	L(b,{Position=UDim2.new(0,0,1,-22),Size=UDim2.new(1,0,0,20),Text=name,TextSize=18})
	b.Activated:Connect(function() pick(name) end)
	tabs[name]=b
	local pf=N("ScrollingFrame",{Position=UDim2.fromOffset(0,76),Size=UDim2.new(1,0,1,-110),BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=4,AutomaticCanvasSize=Enum.AutomaticSize.Y,CanvasSize=UDim2.new(),Visible=false},panel)
	N("UIPadding",{PaddingTop=UDim.new(0,6),PaddingLeft=UDim.new(0,8)},pf)
	N("UIGridLayout",{CellSize=UDim2.fromOffset(160,96),CellPadding=UDim2.fromOffset(10,10),SortOrder=Enum.SortOrder.LayoutOrder},pf)
	pages[name]=pf
	for i,d in ipairs(t[3]) do
		local tile=N("TextButton",{BackgroundColor3=Color3.fromRGB(44,44,50),Text="",AutoButtonColor=false,BorderSizePixel=0,LayoutOrder=i},pf)
		R(tile,5)
		local st=N("UIStroke",{Thickness=2,ApplyStrokeMode=Enum.ApplyStrokeMode.Border},tile)
		local body=L(tile,{Position=UDim2.fromOffset(4,0),Size=UDim2.new(1,-8,1,-28),TextSize=30})
		local bar=N("Frame",{AnchorPoint=Vector2.new(0,1),Position=UDim2.fromScale(0,1),Size=UDim2.new(1,0,0,28),BackgroundColor3=GREY,BorderSizePixel=0},tile)
		local g=N("UIGradient",{Enabled=false},bar)
		L(bar,{Size=UDim2.fromScale(1,1),Text=d.name,TextSize=18})
		tile.Activated:Connect(function() d.click() render() end)
		items[#items+1]={body=body,bar=bar,g=g,st=st,d=d}
	end
end

local perfOn,offOn,flingOn
function render()
	for _,it in ipairs(items) do
		local d=it.d
		local on=d.on()
		local c=d.red and RD or CY
		it.body.Text=tostring(d.text())
		it.g.Enabled=on it.g.Color=ColorSequence.new(c[1],c[2])
		it.bar.BackgroundColor3=on and WHT or GREY
		it.st.Color=on and c[1] or Color3.new()
	end
	stat.Text=("%s | Map: %s | Coins left: %d | Got: %d/%d"):format(S.status,S.map,S.coins,S.count,GOAL)
	if S.perf~=perfOn then perfOn=S.perf perf(S.perf) end
	if S.off3d~=offOn then offOn=S.off3d pcall(function() RS:Set3dRenderingEnabled(not S.off3d) end) end
	if S.fling~=flingOn then flingOn=S.fling antifling(S.fling) end
end

local close=N("TextButton",{AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-6,0,6),Size=UDim2.fromOffset(40,60),BackgroundColor3=Color3.fromRGB(190,55,55),Text="",AutoButtonColor=false,BorderSizePixel=0},top)
R(close,4) K(close,1) L(close,{Size=UDim2.fromScale(1,1),Text="X",TextSize=24})
local fab=N("TextButton",{Position=UDim2.new(0,14,.5,-26),Size=UDim2.fromOffset(52,52),BackgroundColor3=BLUE,Text="",AutoButtonColor=false,BorderSizePixel=0},gui)
R(fab,8) K(fab,2) L(fab,{Size=UDim2.fromScale(1,1),Text="CF",TextSize=22})

local function setOpen(v)
	open=v
	if v then panel.Visible=true end
	local t=TS:Create(sc,TweenInfo.new(.2),{Scale=v and fit() or .01})
	t:Play()
	if not v then t.Completed:Once(function() if not open then panel.Visible=false end end) end
end
fab.Activated:Connect(function() setOpen(not open) end)
close.Activated:Connect(function() setOpen(false) end)
UIS.InputBegan:Connect(function(i,p) if not p and i.KeyCode==Enum.KeyCode.RightShift then setOpen(not open) end end)

local drag,ds,sp
top.InputBegan:Connect(function(i)
	if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
		drag,ds,sp=true,i.Position,panel.Position
		i.Changed:Connect(function() if i.UserInputState==Enum.UserInputState.End then drag=false end end)
	end
end)
UIS.InputChanged:Connect(function(i)
	if drag and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
		local d=i.Position-ds
		panel.Position=UDim2.new(sp.X.Scale,sp.X.Offset+d.X,sp.Y.Scale,sp.Y.Offset+d.Y)
	end
end)

---------------------------------------------------------------- start (reload settings after hop)
pick("Farm")
local ok,td=pcall(function() return TP:GetLocalPlayerTeleportData() end)
td=(ok and type(td)=="table") and td or {}
for k,v in pairs(CONFIG) do if td[k]~=nil and type(td[k])==type(v) then S[k]=td[k] end end
if S.mode~="Tween" and S.mode~="Teleport" then S.mode="Tween" end
S.speed=math.clamp(S.speed,5,MAXS)
render()
if td.resume or S.autostart then
	task.spawn(function()
		if not plr.Character then plr.CharacterAdded:Wait() end
		task.wait(3)
		start()
	end)
end
