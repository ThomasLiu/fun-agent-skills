#!/bin/bash
set -e

REPO_DIR="$HOME/Projects/fun-agent-skills"
SKILLS_DIR="$REPO_DIR/skills"
DATA_FILE="$REPO_DIR/data.json"
README_FILE="$REPO_DIR/README.md"

cd "$REPO_DIR"

log() {
    echo "[$(date '+%H:%M:%S')] $1"
}

init_data() {
    if [ ! -f "$DATA_FILE" ]; then
        echo '{"skills": [], "collected_at": null}' > "$DATA_FILE"
    fi
}

get_existing_urls() {
    cat "$DATA_FILE" | jq -r '.skills[].url' 2>/dev/null | grep -v "^null$" || echo ""
}

analyze_skill() {
    local name="$1"
    local url="$2"
    local desc="$3"
    local stars="$4"
    
    local prompt="分析这个 GitHub Repo 是否有梗、有趣、适合发小红书/朋友圈/微博。

Repo 信息：
- 名称: $name
- URL: $url
- 描述: $desc
- 星数: $stars

判断标准（全部满足才 interesting=true）：
1. 有趣/有梗/能玩/恶搞？而不是正经技术工具
2. 能引发讨论？有话题性？
3. 小红书/朋友圈能发？能装逼？
4. 有梗的、轻松的内容？

返回 JSON（只返回 JSON，不要其他内容）：
{\"interesting\": true/false, \"fun_angle\": \"有趣的角度\", \"xhs_topic\": \"小红书话题标签\", \"desc_zh\": \"中文翻译（要接地气、有梗）\"}"
    
    local tmpfile=$(mktemp)
    echo "$prompt" > "$tmpfile"
    claude -p --model minimax/MiniMax-M2.7 < "$tmpfile" 2>/dev/null | grep -A 10 '^{' | head -15
    rm -f "$tmpfile"
}

generate_xhs_content() {
    local name="$1"
    local desc_zh="$2"
    local fun_angle="$3"
    local xhs_topic="$4"
    
    local prompt="为这个 GitHub 项目写一篇小红书种草文案。

项目: $name
简介: $desc_zh
有趣角度: $fun_angle
话题标签: $xhs_topic

要求：
- 标题党风格，要夸张、要震惊、要引发好奇
- 300-500字
- 多 emoji，要活泼
- 可以玩梗、恶搞
- 结尾引导评论/关注
- 语气轻松有趣，像朋友聊天
- 可以加 #话题标签

直接输出文案，不要其他内容。"
    
    local tmpfile=$(mktemp)
    echo "$prompt" > "$tmpfile"
    claude -p --model minimax/MiniMax-M2.7 < "$tmpfile" 2>/dev/null
    rm -f "$tmpfile"
}

collect_skills() {
    # 有趣/接地气的关键词
    local keywords=(
        "funny ai tool"
        "chatbot prompt viral"
        "twitter bot github"
        "reddit bot funny"
        "discord bot prank"
        "老板 模拟器"
        "fake ai"
        "troll bot"
        "boss simulator"
        "girlfriend bot"
        "waifu chat"
        "模拟 角色"
        "viral twitter github"
        "autoresponder bot"
    )
    
    local collected=0
    local analyzed=0
    
    for kw in "${keywords[@]}"; do
        if [ $collected -ge 3 ]; then
            break
        fi
        
        log "搜索: $kw"
        
        local search_result=$(gh search repos "$kw" --sort stars --limit 15 --json name,url,description,stargazersCount 2>/dev/null)
        
        if [ -z "$search_result" ]; then
            continue
        fi
        
        local count=$(echo "$search_result" | jq 'length' 2>/dev/null || echo 0)
        
        for i in $(seq 0 $((count - 1))); do
            if [ $collected -ge 3 ]; then
                break
            fi
            
            if [ $analyzed -ge 15 ]; then
                log "已分析 $analyzed 个"
                break 2
            fi
            
            local repo=$(echo "$search_result" | jq -r ".[$i]")
            local url=$(echo "$repo" | jq -r '.url')
            local name=$(echo "$repo" | jq -r '.name')
            local desc=$(echo "$repo" | jq -r '.description')
            local stars=$(echo "$repo" | jq -r '.stargazersCount')
            
            # 去重
            if echo "$existing_urls" | grep -q "^${url}$"; then
                continue
            fi
            
            analyzed=$((analyzed + 1))
            log "分析 [$analyzed]: $name (⭐ $stars)"
            
            # AI 分析
            local analysis=$(analyze_skill "$name" "$url" "$desc" "$stars")
            log "AI 返回: $analysis"
            
            local interesting=$(echo "$analysis" | jq -r '.interesting // false' 2>/dev/null)
            
            if [ "$interesting" != "true" ]; then
                log "不够有趣，跳过"
                continue
            fi
            
            local fun_angle=$(echo "$analysis" | jq -r '.fun_angle // ""' 2>/dev/null)
            local xhs_topic=$(echo "$analysis" | jq -r '.xhs_topic // ""' 2>/dev/null)
            local desc_zh=$(echo "$analysis" | jq -r '.desc_zh // ""' 2>/dev/null)
            
            # 生成小红书内容
            log "生成小红书内容..."
            local xhs_content=$(generate_xhs_content "$name" "$desc_zh" "$fun_angle" "$xhs_topic")
            
            # 写入 md
            local filename=$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr '/' '-' | tr '.' '-')
            local md_file="$SKILLS_DIR/${filename}.md"
            
            cat > "$md_file" << MDEOF
---
name: $name
url: $url
description: $desc
description_zh: $desc_zh
fun_angle: $fun_angle
xhs_topic: $xhs_topic
stars: $stars
collected_at: $(date '+%Y-%m-%d')
---

# $name

## 中文简介

$desc_zh

## 有趣角度

$fun_angle

## 小红书内容

$xhs_content

## 话题标签

$xhs_topic

## 仓库链接

[GitHub]($url)
MDEOF
            
            # 更新数据
            local new_skill=$(jq -n \
                --arg name "$name" \
                --arg url "$url" \
                --arg desc "$desc" \
                --arg desc_zh "$desc_zh" \
                --arg fun_angle "$fun_angle" \
                --arg xhs_topic "$xhs_topic" \
                --arg filename "$filename" \
                --argjson stars "$stars" \
                '{
                    name: $name,
                    url: $url,
                    description: $desc,
                    description_zh: $desc_zh,
                    fun_angle: $fun_angle,
                    xhs_topic: $xhs_topic,
                    filename: $filename,
                    stars: $stars,
                    collected_at: (now | strftime("%Y-%m-%d"))
                }')
            
            cat "$DATA_FILE" | jq ".skills += [$new_skill]" > "$DATA_FILE.tmp"
            mv "$DATA_FILE.tmp" "$DATA_FILE"
            
            existing_urls="${existing_urls}
${url}"
            collected=$((collected + 1))
            log "✅ 收录: $name"
            
            sleep 2
        done
        
        sleep 1
    done
    
    echo $collected
}

update_readme() {
    local skills=$(cat "$DATA_FILE" | jq '.skills')
    local count=$(echo "$skills" | jq 'length')
    
    {
        echo "# 🦄 Fun Agent Skills"
        echo ""
        echo "> 有趣的 Agent Skills 收集，专注有梗、有话题性的内容素材"
        echo ""
        echo "更新时间: $(date '+%Y-%m-%d') | 共 $count 个 Skills"
        echo ""
        echo "## 📂 分类汇总"
        echo ""
        echo "| # | Skill 名称 | 中文简介 | 仓库链接 | 小红书内容 |"
        echo "|---|------------|----------|----------|------------|"
    } > "$README_FILE"
    
    if [ "$count" -gt 0 ]; then
        echo "$skills" | jq -r 'to_entries[] | "| \(.key + 1) | [\(.value.name)](\(.value.url)) | \(.value.description_zh // .value.description) | [GitHub](\(.value.url)) | [小红书](./skills/\(.value.filename).md) |"' >> "$README_FILE"
        
        echo "" >> "$README_FILE"
        echo "## 🎯 热门推荐" >> "$README_FILE"
        echo "" >> "$README_FILE"
        echo "$skills" | jq -r '.[] | "- **[\(.name)](\(.url))** \(.xhs_topic // "")"' >> "$README_FILE"
    else
        echo "" >> "$README_FILE"
        echo "暂无内容。" >> "$README_FILE"
    fi
}

main() {
    log "开始采集有趣的 Agent Skills..."
    
    init_data
    existing_urls=$(get_existing_urls)
    
    log "已有 $(echo "$existing_urls" | grep -c '^' || echo 0) 个"
    
    local new_count=$(collect_skills)
    update_readme
    
    log "完成！新增 $new_count 个，总计 $(cat "$DATA_FILE" | jq '.skills | length') 个"
}

main
