ngx.update_time()
local begin = ngx.now()
local tn = "user_active_test"
local selector = {name='lxj', age=123, sex=true}

function sha1_test()
    ngx.sha1_bin("")
end
    
function json_test()
    local json = cjson.encode({tn=tn, selector=selector})
    local arr = cjson.decode(json)
end

for i=0,10000 *10 do 
    --str_test()
    json_test()
end

ngx.update_time()
local end_ = ngx.now()
ngx.say("time:", (end_-begin))