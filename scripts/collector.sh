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
    
    local prompt="分析这个 GitHub Repo 是否有话题性、适合做小红书内容。

Repo 信息：
- 名称: $name
- URL: $url
- 描述: $desc
- 星数: $stars

请分析并返回 JSON：
{\"interesting\": true/false, \"reason\": \"原因\", \"clickbaitscore\": 数字, \"topic_angle\": \"内容角度\", \"desc_zh\": \"中文简介\"}"

    echo "$prompt" | claude -p --model minimax/MiniMax-M2.7 2>/dev/null | grep -A 20 '^{' | head -20
}

generate_xhs_content() {
    local name="$1"
    local desc_zh="$2"
    local reason="$3"
    local topic_angle="$4"
    
    local prompt="为这个 AI Agent Skill 写一篇小红书种草文案。

名称: $name
简介: $desc_zh
有趣点: $reason
内容角度: $topic_angle

要求：
- 标题党风格，吸引眼球
- 300-500字
- 多 emoji
- 有话题性
- 结尾引导关注/评论

直接输出文案，不要其他内容。"

    echo "$prompt" | claude -p --model minimax/MiniMax-M2.7 2>/dev/null
}

collect_skills() {
    local keywords=("claude-code skill" "agent skill" "openclaws skill" "cursor rules")
    local collected=0
    local analyzed=0
    
    for kw in "${keywords[@]}"; do
        if [ $collected -ge 3 ]; then
            break
        fi
        
        log "搜索: $kw"
        
        local search_result=$(gh search repos "$kw" --sort stars --limit 20 --json name,url,description,stargazersCount 2>/dev/null)
        
        if [ -z "$search_result" ]; then
            log "搜索失败: $kw"
            continue
        fi
        
        local count=$(echo "$search_result" | jq 'length' 2>/dev/null || echo 0)
        log "找到 $count 个结果"
        
        for i in $(seq 0 $((count - 1))); do
            if [ $collected -ge 3 ]; then
                break
            fi
            
            if [ $analyzed -ge 20 ]; then
                log "已分析 $analyzed 个，停止搜索"
                break 2
            fi
            
            local repo=$(echo "$search_result" | jq -r ".[$i]")
            local url=$(echo "$repo" | jq -r '.url')
            local name=$(echo "$repo" | jq -r '.name')
            local desc=$(echo "$repo" | jq -r '.description')
            local stars=$(echo "$repo" | jq -r '.stargazersCount')
            
            # 去重检查
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
                log "话题性不足，跳过"
                continue
            fi
            
            local reason=$(echo "$analysis" | jq -r '.reason // ""' 2>/dev/null)
            local clickbaitscore=$(echo "$analysis" | jq -r '.clickbaitscore // 5' 2>/dev/null)
            local topic_angle=$(echo "$analysis" | jq -r '.topic_angle // ""' 2>/dev/null)
            local desc_zh=$(echo "$analysis" | jq -r '.desc_zh // ""' 2>/dev/null)
            
            # 生成小红书内容
            log "生成小红书内容..."
            local xhs_content=$(generate_xhs_content "$name" "$desc_zh" "$reason" "$topic_angle")
            
            # 写入 md 文件
            local filename=$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr '/' '-' | tr '.' '-')
            local md_file="$SKILLS_DIR/${filename}.md"
            
            cat > "$md_file" << MDEOF
---
name: $name
url: $url
description: $desc
description_zh: $desc_zh
reason: $reason
topic_angle: $topic_angle
clickbaitscore: $clickbaitscore
stars: $stars
collected_at: $(date '+%Y-%m-%d')
---

# $name

## 中文简介

$desc_zh

## 为什么有趣

$reason

## 内容角度

$topic_angle

## 小红书内容

$xhs_content

## 仓库链接

[GitHub]($url)
MDEOF
            
            # 更新数据文件
            local new_skill=$(jq -n \
                --arg name "$name" \
                --arg url "$url" \
                --arg desc "$desc" \
                --arg desc_zh "$desc_zh" \
                --arg reason "$reason" \
                --arg topic_angle "$topic_angle" \
                --arg filename "$filename" \
                --argjson clickbaitscore "$clickbaitscore" \
                --argjson stars "$stars" \
                '{
                    name: $name,
                    url: $url,
                    description: $desc,
                    description_zh: $desc_zh,
                    reason: $reason,
                    topic_angle: $topic_angle,
                    filename: $filename,
                    clickbaitscore: $clickbaitscore,
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
        echo "> 有趣的 Agent Skills 收集，专注有话题性、能博眼球的内容素材"
        echo ""
        echo "更新时间: $(date '+%Y-%m-%d') | 共 $count 个 Skills"
        echo ""
        echo "## 📂 分类汇总"
        echo ""
        echo "| # | Skill 名称 | 中文简介 | 仓库链接 | 小红书内容 |"
        echo "|---|------------|----------|----------|------------|"
    } > "$README_FILE"
    
    if [ "$count" -gt 0 ]; then
        echo "$skills" | jq -r 'sort_by(.clickbaitscore // 0) | reverse | to_entries[] | "| \(.key + 1) | [\(.value.name)](\(.value.url)) | \(.value.description_zh // .value.description) | [GitHub](\(.value.url)) | [小红书](./skills/\(.value.filename).md) |"' >> "$README_FILE"
        
        echo "" >> "$README_FILE"
        echo "## 🎯 热门推荐" >> "$README_FILE"
        echo "" >> "$README_FILE"
        echo "$skills" | jq -r 'sort_by(.clickbaitscore // 0) | reverse | .[0:3][] | "- **[\(.name)](\(.url))** - \(.description_zh // .description)"' >> "$README_FILE"
    else
        echo "" >> "$README_FILE"
        echo "暂无内容。" >> "$README_FILE"
    fi
}

main() {
    log "开始采集有趣的 Agent Skills..."
    
    init_data
    existing_urls=$(get_existing_urls)
    
    log "已有 $(echo "$existing_urls" | grep -c '^' || echo 0) 个 Skills"
    
    local new_count=$(collect_skills)
    update_readme
    
    log "完成！新增 $new_count 个 Skills，总计 $(cat "$DATA_FILE" | jq '.skills | length') 个"
}

main
