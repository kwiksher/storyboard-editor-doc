local key    = "ACTIVATION_KEY"
local email  = "support@kwiksher.com"
local serial = "AAAABBBBCCCC"
----


-- https://github.com/catwell/lua-multipart-post

local ltn12 = require "ltn12"
--local url = require "socket.url"
-- https://github.com/kernelsauce/turbo/blob/master/turbo/escape.lua

function escape(s)
    return (string.gsub(s, "[}{\">/<'&]", {
        ["&"] = "&amp;",
        ["<"] = "&lt;",
        [">"] = "&gt;",
        ['"'] = "&quot;",
        ["'"] = "&#39;",
        ["/"] = "&#47;"
    }))
end

local _M = {}

_M.CHARSET = "UTF-8"
_M.LANGUAGE = ""

local function fmt(p, ...)
    if select('#', ...) == 0 then
        return p
    end
    return string.format(p, ...)
end

local function tprintf(t, p, ...)
    t[#t+1] = fmt(p, ...)
end

local function section_header(r, k, extra)
    tprintf(r, "content-disposition: form-data; name=\"%s\"", k)
    if extra.filename then
        tprintf(r, "; filename=\"%s\"", extra.filename)
        tprintf(
            r, "; filename*=%s'%s'%s",
            _M.CHARSET, _M.LANGUAGE, escape(extra.filename)
        )
    end
    if extra.content_type then
        tprintf(r, "\r\ncontent-type: %s", extra.content_type)
    end
    if extra.content_transfer_encoding then
        tprintf(
            r, "\r\ncontent-transfer-encoding: %s",
            extra.content_transfer_encoding
        )
    end
    tprintf(r, "\r\n\r\n")
end

local function gen_boundary()
  local t = {"BOUNDARY-"}
  for i=2,17 do t[i] = string.char(math.random(65, 90)) end
  t[18] = "-BOUNDARY"
  return table.concat(t)
end

local function encode_header_to_table(r, k, v, boundary)
    local _t = type(v)

    tprintf(r, "--%s\r\n", boundary)
    if _t == "string" then
        section_header(r, k, {})
    elseif _t == "table" then
        assert(v.data, "invalid input")
        local extra = {
            filename = v.filename or v.name,
            content_type = v.content_type or v.mimetype
                or "application/octet-stream",
            content_transfer_encoding = v.content_transfer_encoding
                or "binary",
        }
        section_header(r, k, extra)
    else
        error(string.format("unexpected type %s", _t))
    end
end

local function encode_header_as_source(k, v, boundary, ctx)
    local r = {}
    encode_header_to_table(r, k, v, boundary, ctx)
    local s = table.concat(r)
    if ctx then
        ctx.headers_length = ctx.headers_length + #s
    end
    return ltn12.source.string(s)
end

local function data_len(d)
    local _t = type(d)

    if _t == "string" then
        return string.len(d)
    elseif _t == "table" then
        if type(d.data) == "string" then
            return string.len(d.data)
        end
        if d.len then return d.len end
        error("must provide data length for non-string datatypes")
    end
end

local function content_length(t, boundary, ctx)
    local r = ctx and ctx.headers_length or 0
    for k, v in pairs(t) do
        if not ctx then
            local tmp = {}
            encode_header_to_table(tmp, k, v, boundary)
            r = r + #table.concat(tmp)
        end
        r = r + data_len(v) + 2; -- `\r\n`
    end
    return r + #boundary + 6; -- `--BOUNDARY--\r\n`
end

local function get_data_src(v)
    local _t = type(v)
    if v.source then
        return v.source
    elseif _t == "string" then
        return ltn12.source.string(v)
    elseif _t == "table" then
        _t = type(v.data)
        if _t == "string" then
            return ltn12.source.string(v.data)
        elseif _t == "table" then
            return ltn12.source.table(v.data)
        elseif _t == "userdata" then
            return ltn12.source.file(v.data)
        elseif _t == "function" then
            return v.data
        end
    end
    error("invalid input")
end

local function set_ltn12_blksz(sz)
    assert(type(sz) == "number", "set_ltn12_blksz expects a number")
    ltn12.BLOCKSIZE = sz
end

_M.set_ltn12_blksz = set_ltn12_blksz

local function source(t, boundary, ctx)
    print (boundary, ctx)
    local sources, n = {}, 1
    for k, v in pairs(t) do
        print ("source", k, v)
        sources[n] = encode_header_as_source(k, v, boundary, ctx)
        sources[n+1] = get_data_src(v)
        sources[n+2] = ltn12.source.string("\r\n")
        n = n + 3
    end
    sources[n] = ltn12.source.string(string.format("--%s--\r\n", boundary))
    return ltn12.source.cat(unpack(sources))
end

_M.source = source

function _M.gen_request(t)
    local boundary = gen_boundary()
    -- This is an optimization to avoid re-encoding headers twice.
    -- The length of the headers is stored when computing the source,
    -- and re-used when computing the content length.
    local ctx = {headers_length = 0}
    return {
        method = "POST",
        source = source(t, boundary, ctx),
        headers = {
            ["content-length"] = content_length(t, boundary, ctx),
            ["content-type"] = fmt(
                "multipart/form-data; boundary=\"%s\"", boundary
            ),
        },
    }
end

function _M.encode(t, boundary)
    boundary = boundary or gen_boundary()
    local r = {}
    assert(ltn12.pump.all(
        (source(t, boundary)),
        (ltn12.sink.table(r))
    ))
    return table.concat(r), boundary
end


_M.split = function(str, pat)
    local t = {}  -- NOTE: use {n = 0} in Lua-5.0
    local fpat = "(.-)" .. pat
    local last_end = 1
    local s, e, cap = str:find(fpat, 1)
    while s do
       if s ~= 1 or cap ~= "" then
         table.insert(t,cap)
       end
       last_end = e+1
       s, e, cap = str:find(fpat, last_end)
    end
    if last_end <= #str then
       cap = str:sub(last_end)
       table.insert(t, cap)
    end
    return t
 end
 -----------------------------------------------
 --
 -----------------------------------------------
 
 _M.getUserDir = function()
    local test = system.pathForFile("data.txt",system.ApplicationSupportDirectory);
    if system.getInfo("platform") =="win32" then
       local arr = M.split(test, '\\')
       --print (arr[3]) -- C:\Users\ymmtny\AppData\Local\Corona Labs
       return arr[3]
    elseif system.getInfo("platform") == "macos" then
       local arr = _M.split(test, '/')
       --print (arr[2]) -- /Users/ymmtny/Library/Application Support/Corona Simulator/
       return arr[2]
    end
 end

 local bodyReq, boundary = _M.encode( {activation_code=key:upper(), serial=serial,  email=email:lower(), user_dir=userDir})

 print (bodyReq, bodyReq)