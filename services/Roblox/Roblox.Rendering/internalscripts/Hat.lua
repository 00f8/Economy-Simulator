-- Hat v1.0.1a

assetUrl, fileExtension, x, y, baseUrl = %assetUrl%, %fileExtension%, %x%, %y%, %baseUrl%

pcall(function() game:GetService("ContentProvider"):SetBaseUrl(baseUrl) end)
game:GetService("ScriptContext").ScriptsDisabled = true

game:GetObjects(assetUrl)[1].Parent = workspace

return game:GetService("ThumbnailGenerator"):Click(fileExtension, x, y, --[[hideSky = ]] true, --[[crop =]] true)