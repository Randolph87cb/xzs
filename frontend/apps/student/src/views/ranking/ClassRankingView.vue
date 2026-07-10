<template>
  <section class="class-ranking" v-loading="loading">
    <header class="class-ranking__header">
      <div>
        <p class="class-ranking__eyebrow">班级排行榜</p>
        <h1>同班学习表现</h1>
        <span>按正确率、答题量、改错提交和重提次数综合排序。</span>
      </div>
      <el-button @click="loadRanking">刷新</el-button>
    </header>

    <el-alert
      v-if="errorMessage"
      :title="errorMessage"
      type="error"
      show-icon
      :closable="false"
    />

    <el-empty v-if="!loading && ranking.length === 0" description="暂无班级排行榜数据" />

    <template v-else>
      <section class="class-ranking__summary">
        <article class="class-ranking__mine">
          <span>我的排名</span>
          <strong>{{ myRanking ? `第 ${myRanking.rank} 名` : '暂无排名' }}</strong>
          <p>{{ previousGapText }}</p>
        </article>
        <article v-for="item in topThree" :key="item.userId" class="class-ranking__podium" :class="`is-rank-${item.rank}`">
          <span>第 {{ item.rank }} 名</span>
          <strong>{{ displayName(item) }}</strong>
          <p>{{ formatPercent(item.accuracyRate) }} 正确率 · {{ item.questionCount }} 题</p>
        </article>
      </section>

      <section class="class-ranking__table-section">
        <div class="class-ranking__section-title">
          <h2>完整排行</h2>
          <el-tag effect="plain">{{ ranking.length }} 人</el-tag>
        </div>
        <el-table :data="ranking" row-key="userId" class="class-ranking__table">
          <el-table-column prop="rank" label="排名" width="86">
            <template #default="{ row }">
              <span class="class-ranking__rank" :class="{ 'is-top': row.rank <= 3 }">{{ row.rank }}</span>
            </template>
          </el-table-column>
          <el-table-column label="学生" min-width="150">
            <template #default="{ row }">
              <div class="class-ranking__student">
                <strong>{{ displayName(row) }}</strong>
                <span>{{ row.userName }}</span>
              </div>
            </template>
          </el-table-column>
          <el-table-column label="正确率" width="116">
            <template #default="{ row }">{{ formatPercent(row.accuracyRate) }}</template>
          </el-table-column>
          <el-table-column prop="questionCount" label="答题数" width="104" />
          <el-table-column prop="correctCount" label="答对数" width="104" />
          <el-table-column prop="correctionCount" label="改错数" width="104" />
          <el-table-column prop="resubmitCount" label="重提次数" width="104" />
          <el-table-column label="与上一名差距" min-width="190">
            <template #default="{ row }">{{ gapText(row) }}</template>
          </el-table-column>
        </el-table>
      </section>
    </template>
  </section>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { getClassRanking, type ClassRankingItem } from '@xzs/api-client'
import { useUserStore } from '@/stores/user'

const userStore = useUserStore()
const loading = ref(false)
const errorMessage = ref('')
const ranking = ref<ClassRankingItem[]>([])

const topThree = computed(() => ranking.value.filter((item) => item.rank <= 3).slice(0, 3))
const myRanking = computed(() => {
  const userId = userStore.userInfo?.id
  if (userId != null) {
    const matchById = ranking.value.find((item) => item.userId === userId)
    if (matchById) {
      return matchById
    }
  }

  return ranking.value.find((item) => item.userName === userStore.userName) ?? null
})
const previousGapText = computed(() => (myRanking.value ? gapText(myRanking.value) : '完成一次练习后即可参与班级排行'))

onMounted(loadRanking)

async function loadRanking() {
  loading.value = true
  errorMessage.value = ''
  try {
    const result = await getClassRanking()
    if (result.code === 1) {
      ranking.value = result.response ?? []
    } else {
      ranking.value = []
      errorMessage.value = result.message || '班级排行榜加载失败'
    }
  } catch {
    ranking.value = []
    errorMessage.value = '班级排行榜加载失败'
  } finally {
    loading.value = false
  }
}

function displayName(item: ClassRankingItem) {
  return item.nickName || item.realName || item.userName
}

function formatPercent(value: number) {
  const percent = value > 1 ? value : value * 100
  return `${percent.toFixed(1)}%`
}

function gapText(item: ClassRankingItem) {
  if (item.rank <= 1) {
    return '当前保持班级领先'
  }

  const previous = ranking.value.find((candidate) => candidate.rank === item.rank - 1)
  if (!previous) {
    return '上一名数据暂不可用'
  }

  const questionGap = Math.max(previous.questionCount - item.questionCount, 0)
  const accuracyGap = Math.max(normalizeRate(previous.accuracyRate) - normalizeRate(item.accuracyRate), 0)

  if (questionGap === 0 && accuracyGap === 0) {
    return '与上一名差距很小'
  }

  const parts: string[] = []
  if (accuracyGap > 0) {
    parts.push(`正确率差 ${(accuracyGap * 100).toFixed(1)}%`)
  }
  if (questionGap > 0) {
    parts.push(`答题数差 ${questionGap} 题`)
  }

  return parts.join('，')
}

function normalizeRate(value: number) {
  return value > 1 ? value / 100 : value
}
</script>

<style scoped lang="scss">
.class-ranking {
  display: grid;
  gap: 20px;
}

.class-ranking__header,
.class-ranking__summary > article,
.class-ranking__table-section {
  border: 1px solid var(--xzs-border);
  border-radius: var(--xzs-radius);
  background: var(--xzs-surface);
}

.class-ranking__header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  padding: 22px 24px;
}

.class-ranking__eyebrow {
  margin: 0 0 6px;
  color: var(--xzs-primary);
  font-size: 14px;
  font-weight: 700;
}

.class-ranking h1,
.class-ranking h2,
.class-ranking p {
  margin: 0;
}

.class-ranking h1 {
  color: var(--xzs-text);
  font-size: 24px;
}

.class-ranking__header span {
  display: block;
  margin-top: 8px;
  color: var(--xzs-text-muted);
}

.class-ranking__summary {
  display: grid;
  grid-template-columns: 1.2fr repeat(3, minmax(0, 1fr));
  gap: 14px;
}

.class-ranking__summary > article {
  display: grid;
  align-content: start;
  gap: 8px;
  min-height: 132px;
  padding: 18px;
}

.class-ranking__summary span {
  color: var(--xzs-text-muted);
  font-size: 13px;
}

.class-ranking__summary strong {
  overflow: hidden;
  color: var(--xzs-text);
  font-size: 22px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.class-ranking__summary p {
  color: var(--xzs-text-muted);
  line-height: 1.6;
}

.class-ranking__mine {
  border-color: rgb(23 105 255 / 38%);
  background: linear-gradient(135deg, #f7fbff 0%, #fff 72%);
}

.class-ranking__mine strong {
  color: var(--xzs-primary);
  font-size: 30px;
}

.class-ranking__podium.is-rank-1 {
  border-color: rgb(240 123 34 / 38%);
  background: #fffaf5;
}

.class-ranking__podium.is-rank-2 {
  border-color: rgb(97 112 138 / 30%);
  background: #fbfcff;
}

.class-ranking__podium.is-rank-3 {
  border-color: rgb(19 166 107 / 28%);
  background: #f8fffb;
}

.class-ranking__table-section {
  display: grid;
  gap: 14px;
  padding: 18px;
}

.class-ranking__section-title {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
}

.class-ranking__section-title h2 {
  color: var(--xzs-text);
  font-size: 18px;
}

.class-ranking__rank {
  display: inline-grid;
  place-items: center;
  width: 30px;
  height: 30px;
  border-radius: 999px;
  background: var(--xzs-surface-soft);
  color: var(--xzs-text);
  font-weight: 700;
}

.class-ranking__rank.is-top {
  background: #fff0df;
  color: var(--xzs-warning);
}

.class-ranking__student {
  display: grid;
  gap: 2px;
}

.class-ranking__student strong {
  color: var(--xzs-text);
}

.class-ranking__student span {
  color: var(--xzs-text-muted);
  font-size: 13px;
}

@media (max-width: 900px) {
  .class-ranking__header {
    align-items: stretch;
    flex-direction: column;
  }

  .class-ranking__summary {
    grid-template-columns: 1fr;
  }
}
</style>
