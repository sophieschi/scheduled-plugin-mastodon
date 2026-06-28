local api, CHILDS, CONTENTS = ...

local json = require "json"
local utf8 = require "utf8"
local utils = require(api.localized "utils")
local anims = require(api.localized "anims")

local show_logo = true
local char_per_sec = 7
local include_in_scroller = true
local shading
local toot_color, profile_color
local name_font
local info_font
local text_font
local name_size
local text_size
local margin = 10
local text_over_under
local profile_over_under
local ignore_non_media_posts = false
local logo = resource.load_image{
    file = api.localized "mastodon-logo.png"
}
local max_text_lines = 10

local playlist = {}

local M = {}

local function wrap(str, font, size, max_w)
    local lines = {}
    local space_w = font:width(" ", size)

    local remaining = max_w
    local line = {}

    local tokens = {}
    for token in utf8.gmatch(str, "%S+") do
        local w = font:width(token, size)
        if w >= max_w then
            while #token > 0 do
                local cut = #token
                for take = 1, #token do
                    local sub_token = utf8.sub(token, 1, take)
                    w = font:width(sub_token, size)
                    if w >= max_w then
                        cut = take-1
                        break
                    end
                end
                tokens[#tokens+1] = utf8.sub(token, 1, cut)
                token = utf8.sub(token, cut+1)
            end
        else
            tokens[#tokens+1] = token
        end
    end
    for _, token in ipairs(tokens) do
        local w = font:width(token, size)
        if remaining - w < 0 then
            lines[#lines+1] = table.concat(line, "")
            line = {}
            remaining = max_w
        end
        line[#line+1] = token
        line[#line+1] = " "
        remaining = remaining - w - space_w
    end
    if #line > 0 then
        lines[#lines+1] = table.concat(line, "")
    end
    return lines
end

local function only_contains_hashtags(text)
    for token in utf8.gmatch(text, "%S+") do
        if string.sub(token, 1, 1) ~= "#" then
            return false
        end
    end
    return true
end

function M.updated_tootlist_json(toots)
    playlist = {}

    local scroller = {}
    for idx = 1, #toots do
        local toot = toots[idx]

        local ok, profile, image

        ok, profile = pcall(resource.open_file, api.localized(toot.account.avatar_static))
        if not ok then
            print("cannot use this toot. profile image missing", profile)
            profile = nil
        end

        if toot.media_attachment ~= '' then
            -- TODO: load more than only the first image
            ok, image = pcall(resource.open_file, api.localized(toot.media_attachment))
            if not ok then
                print("cannot open image", image)
                image = nil
            end
        end

        if profile then
            if not ignore_non_media_posts or image then
                playlist[#playlist+1] = {
                    acct = toot.account.acct,
                    display_name = toot.account.display_name,
                    text = toot.content,
                    profile = profile,
                    image = image,
                    created_at = toot.created_at,
                }
                print("toot created at" .. toot.created_at)
            end
            if include_in_scroller and not only_contains_hashtags(toot.content) then
                scroller[#scroller+1] = {
                    text = toot.content,
                    image = profile,
                }
            end
        end
    end

    api.update_data("scroller", scroller)
end

function M.updated_config_json(config)
    print "config updated"

    name_font = resource.load_font(api.localized(config.name_font.asset_name))
    info_font = resource.load_font(api.localized(config.info_font.asset_name))
    text_font = resource.load_font(api.localized(config.text_font.asset_name))
    name_size = config.name_size
    text_size = config.text_size

    include_in_scroller = config.include_in_scroller
    show_logo = config.show_logo
    toot_color = config.toot_color
    profile_color = config.profile_color
    margin = config.margin
    text_over_under = config.text_over_under
    profile_over_under = config.profile_over_under
    ignore_non_media_posts = config.ignore_non_media_posts
    max_text_lines = config.max_text_lines

    if config.shading > 0.0 then
        shading = resource.create_colored_texture(0,0,0,config.shading)
    else
        shading = nil
    end

    node.gc()
end

local toot_gen = util.generator(function()
    return playlist
end)

function M.task(starts, ends, config, x1, y1, x2, y2)
    local boundingbox_height = y2-y1
    local boundingbox_width = x2-x1

    print("ACTUAL SCREEN SIZE " .. boundingbox_width .. "x" .. boundingbox_height)

    local toot = toot_gen.next()

    local profile = resource.load_image{
        file = toot.profile:copy(),
        mipmap = true,
    }

    api.wait_t(starts-2.5)

    local image, video

    if toot.image then
        image = resource.load_image{
            file = toot.image:copy(),
        }
    end
    api.wait_t(starts-0.3)

    local age = api.clock.unix() - toot.created_at
    if age < 100 then
        age = string.format("%d Sekunden", age)
    elseif age < 3600 then
        age = string.format("%d Minuten", age/60)
    elseif age < 86400 then
        age = string.format("%d Stunden", age/3600)
    else
        age = string.format("%d Tagen", age/86400)
    end

    local a = anims.Area(boundingbox_width, boundingbox_height)

    local S = starts
    local E = ends

    local function mk_profile_box(x, y)
        local name = toot.acct
        if toot.display_name ~= '' then
            name = toot.display_name
        end
        local info = "@"..toot.acct..", vor "..age..""

        local profile_image_size = name_size*1.6

        if shading then
            local profile_width = math.max(
                name_font:width(name, name_size),
                name_font:width(info, name_size*0.6)
            )
            a.add(anims.moving_image_raw(S,E, shading,
                x, y,
                x+profile_image_size+profile_width+2*margin+10, y+profile_image_size+2*margin,
                1
            ))
        end
        a.add(anims.moving_font(S, E, name_font,
            x+profile_image_size+10+margin, y+margin,
            name, name_size,
            profile_color.r, profile_color.g, profile_color.b, profile_color.a
        ))
        a.add(anims.moving_font(S, E, info_font,
            x+profile_image_size+10+margin, y+name_size+margin,
            info, name_size*0.6,
            profile_color.r, profile_color.g, profile_color.b, profile_color.a*0.8
        ))
        S = S+0.1
        a.add(anims.moving_image_raw(S,E, profile,
            x+margin, y+margin,
            x+margin+profile_image_size, y+margin+profile_image_size,
            1
        ))
    end

    local lines = wrap(
        toot.text, text_font, text_size, boundingbox_width-2*margin
    )

    local actual_lines
    if max_text_lines > 0 then
        if image then
            actual_lines = math.min(#lines, math.floor(max_text_lines/2))
        else
            actual_lines = math.min(#lines, max_text_lines)
        end
    else
        actual_lines = #lines
    end

    local function mk_content_box(x, y)
        if shading then
            local text_width = 0
            for idx = 1, actual_lines do
                local line = lines[idx]
                text_width = math.max(text_width, text_font:width(line, text_size))
            end
            a.add(anims.moving_image_raw(S,E, shading,
                x, y,
                x+text_width+2*margin, y+actual_lines*text_size+2*margin,
                1
            ))
        end
        y = y + margin
        for idx = 1, actual_lines do
            local line = lines[idx]
            a.add(anims.moving_font(S, E, text_font,
                x+margin, y,
                line, text_size,
                toot_color.r, toot_color.g, toot_color.b, toot_color.a
            ))
            S = S+0.1
            y = y+text_size
        end
    end

    local obj = image
    local text_height = actual_lines*text_size + 2*margin
    local profile_height = text_size*1.6 + 2*margin + 5

    print(boundingbox_width, boundingbox_height, text_height, text_over_under)

    if obj then
        local width, height = obj:size()
        print("ASSET SIZE", width, height, obj)
        local remaining_height_for_image = boundingbox_height
        local profile_y

        if text_over_under == "under" then
            remaining_height_for_image = remaining_height_for_image - text_height - 2*margin
        end

        if profile_over_under == "under" or profile_over_under == "over" then
            remaining_height_for_image = remaining_height_for_image - profile_height - 2*margin
        end

        local x1, y1, x2, y2 = util.scale_into(boundingbox_width, remaining_height_for_image, width, height)

        if profile_over_under == "over" then
            y1 = y1 + profile_height + 2*margin
            y2 = y2 + profile_height + 2*margin
        end

        print(x1, y1, x2, y2)
        a.add(anims.moving_image_raw(S,E, obj,
            x1, y1, x2, y2, 1
        ))
        mk_content_box(0, boundingbox_height - text_height)

        if profile_over_under == "under" then
            profile_y = boundingbox_height - text_height - profile_height - 4*margin
        elseif profile_over_under == "over" then
            profile_y = 0
        else
            profile_y = margin
        end

        mk_profile_box(0, profile_y)
    else
        local text_y = math.min(
            math.max(
                text_size*1.6+3*margin,
                130
            ),
            boundingbox_height-text_height
        )
        mk_content_box(0, text_y)
        mk_profile_box(0, 0)
    end

    if show_logo then
        a.add(anims.logo(S, E, boundingbox_width-130, boundingbox_height-130, logo, 100))
    end

    for now in api.frame_between(starts, ends) do
        a.draw(now, x1, y1, x2, y2)
    end

    profile:dispose()

    if image then
        image:dispose()
    end
end

return M
