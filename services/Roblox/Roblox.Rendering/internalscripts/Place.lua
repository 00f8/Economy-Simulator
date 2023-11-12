-- Place v1.0.2a

assetUrl, fileExtension, x, y, baseUrl, universeId = %assetUrl%, %fileExtension%, %x%, %y%, %baseUrl%, %universeId%

pcall(function() game:GetService("ContentProvider"):SetBaseUrl(baseUrl) end)
if universeId ~= nil then
	pcall(function() game:SetUniverseId(universeId) end)
end

game:Load(assetUrl)

game:GetService("ScriptContext").ScriptsDisabled = true
game:GetService("StarterGui").ShowDevelopmentGui = false

return game:GetService("ThumbnailGenerator"):Click(fileExtension, x, y, --[[hideSky = ]] false)