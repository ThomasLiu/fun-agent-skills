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

# 初始化数据文件
init_data() {
    if [ ! -f "$DATA_FILE" ]; then
        echo '{"skills": [], "collected_at": null}' > "$DATA_FILE"
    fi
}

# 获取已有的 skill URL 列表（去重）
get_existing_urls() {
    cat "$DATA_FILE" | jq -r '.skills[].url // []' 2>/dev/null || echo ""
}

# 搜索有趣的 skills
search_interesting_skills() {
    local keywords=("claude-code skill" "agent skill" "openclaws skill" "cursor rules" "ai agent prompt")
    local results=()
    
    for kw in "${keywords[@]}"; do
        log "搜索: $kw"
        local repos=$(gh search repos "$kw" --sort stars --limit 30 --json name,url,description,stargazersCount 2>/dev/null | jq -r '.[] | @json' 2>/dev/null || echo "")
        if [ -n "$repos" ]; then
            results+=($repos)
        fi
        sleep 1
    done
    
    echo "${results[@]}" | jq -s 'unique_by(.url)'
}

# 分析 skill 是否有话题性
analyze_interesting() {
    local repo_json="$1"
    local name=$(echo "$repo_json" | jq -r '.name')
    local url=$(echo "$repo_json" | jq -r '.url')
    local desc=$(echo "$repo_json" | jq -r '.description')
    local stars=$(echo "$repo_json" | jq -r '.stargazersCount')
    
    # 调用 AI 分析是否有话题性
    local analysis=$(claude -p --model minimax/MiniMax-M2.7 2>/dev/null << 'EOF'
分析这个 GitHub Repo 是否有话题性、适合做小红书内容。

Repo 信息：
- 名称: NAME
- URL: URL
- 描述: DESC
- 星数: STARS

请分析：
1. 是否有话题性？（新奇、有趣、引发好奇）
2. 是否适合做内容？（有亮点可挖）
3. 博眼球程度？（1-10分）

只返回 JSON 格式：
{"interesting": true/false, "reason": "原因", "clickbaitscore": 数字, "topic_angle": "可以做哪个角度的内容"}
EOF
)
    
    echo "$analysis"
}

# 写入 skill md 文件
write_skill_md() {
    local name="$1"
    local url="$2"
    local desc="$3"
    local desc_zh="$4"
    local reason="$5"
    local topic_angle="$6"
    local xhs_content="$7"
    
    local filename=$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr '/' '-')
    local md_file="$SKILLS_DIR/${filename}.md"
    
    cat > "$md_file" << 'XMARK'
---
name: NAME
url: URL
description: DESC
description_zh: DESC_ZH
reason: REASON
topic_angle: ANGLE
xhs_content: |
XHS_CONTENT
---

# NAME

## 中文简介

DESC_ZH

## 为什么有趣

REASON

## 内容角度

ANGLE

## 小红书内容

XHS_CONTENT

## 仓库链接

[GitHub](URL)
XMARK

    # 替换占位符
    sed -i '' "s/NAME/$name/g" "$md_file"
    sed -i '' "s|URL|$url|g" "$md_file"
    sed -i '' "s/DESC/$desc/g" "$md_file"
    sed -i '' "s/DESC_ZH/$desc_zh/g" "$md_file"
    sed -i '' "s/REASON/$reason/g" "$md_file"
    sed -i '' "s/ANGLE/$topic_angle/g" "$md_file"
    sed -i '' "s|XHS_CONTENT|$xhs_content|g" "$md_file"
    
    echo "$md_file"
}

# 生成小红书内容
generate_xhs_content() {
    local name="$1"
    local desc_zh="$2"
    local reason="$3"
    local topic_angle="$4"
    
    claude -p --model minimax/MiniMax-M2.7 2>/dev/null << 'EOF'
为这个 AI Agent Skill 写一篇小红书种草文案。

名称: NAME
简介: DESC_ZH
有趣点: REASON
内容角度: ANGLE

要求：
- 标题党风格，吸引眼球
- 300-500字
- 有 emoji
- 有话题性
- 结尾引导关注/评论

直接输出文案，不要其他内容。
EOF
}

# 更新 README 汇总页面
update_readme() {
    local skills=$(cat "$DATA_FILE" | jq '.skills')
    local count=$(echo "$skills" | jq 'length')
    
    cat > "$README_FILE" << 'HEADER'
# 🦄 Fun Agent Skills

> 有趣的 Agent Skills 收集，专注有话题性、能博眼球的内容素材

更新时间: DATE | 共 COUNT 个 Skills

## 📂 分类汇总

| # | Skill 名称 | 中文简介 | 仓库链接 | 小红书内容 |
|---|------------|----------|----------|------------|

## 🎯 热门推荐

HEADER

    # 按话题性排序，取前 10
    echo "$skills" | jq -r 'sort_by(.clickbaitscore // 0) | reverse | .[0:10][] | "| \(.name) | \(.description_zh // .description) | [GitHub](\(.url)) | [小红书](\"./skills/\(.filename).md\") |"' >> "$README_FILE"
    
    # 替换日期和数量
    sed -i '' "s/DATE/$(date '+%Y-%m-%d')/g" "$README_FILE"
    sed -i '' "s/COUNT/$count/g" "$README_FILE"
}

# 主流程
main() {
    log "开始采集有趣的 Agent Skills..."
    
    init_data
    
    local existing_urls=$(get_existing_urls)
    local search_results=$(search_interesting_skills)
    
    local new_count=0
    local analyzed=0
    
    # 取前 10 个搜索结果分析
    echo "$search_results" | jq -r '.[0:10] | .[] | @json' | while read repo_json; do
        local url=$(echo "$repo_json" | jq -r '.url')
        local name=$(echo "$repo_json" | jq -r '.name')
        
        # 去重
        if echo "$existing_urls" | grep -q "$url"; then
            log "跳过已收录: $name"
            continue
        fi
        
        log "分析: $name"
        
        # AI 分析
        local analysis=$(analyze_interesting "$repo_json")
        local interesting=$(echo "$analysis" | jq -r '.interesting // false')
        
        if [ "$interesting" != "true" ]; then
            log "话题性不足，跳过: $name"
            continue
        fi
        
        local reason=$(echo "$analysis" | jq -r '.reason // ""')
        local clickbaitscore=$(echo "$analysis" | jq -r '.clickbaitscore // 5')
        local topic_angle=$(echo "$analysis" | jq -r '.topic_angle // ""')
        local desc=$(echo "$repo_json" | jq -r '.description')
        local stars=$(echo "$repo_json" | jq -r '.stargazersCount')
        
        # 生成中文简介（调用 AI 翻译）
        local desc_zh=$(claude -p --model minimax/MiniMax-M2.7 2>/dev/null << 'EOF'
翻译这段话为中文，保持简洁有吸引力：

TEXT

只输出中文翻译，不要其他内容。
EOF
)
        
        # 生成小红书内容
        local xhs_content=$(generate_xhs_content "$name" "$desc_zh" "$reason" "$topic_angle")
        
        # 写入 md 文件
        local filename=$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr '/' '-')
        write_skill_md "$name" "$url" "$desc" "$desc_zh" "$reason" "$topic_angle" "$xhs_content"
        
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
        
        existing_urls="$existing_urls\n$url"
        new_count=$((new_count + 1))
        analyzed=$((analyzed + 1))
        
        # 只取 3 个新的
        if [ $new_count -ge 3 ]; then
            break
        fi
        
        sleep 2
    done
    
    # 更新 README
    update_readme
    
    log "完成！新增 $new_count 个 Skills，总计 $(cat "$DATA_FILE" | jq '.skills | length') 个"
}

main
