<template>
  <section class="record-list">
    <header class="record-list__header">
      <h1>考试记录</h1>
      <el-button :loading="loading" @click="loadRecords">刷新</el-button>
    </header>

    <el-table v-loading="loading" :data="records" row-key="id" @row-click="selectRecord">
      <el-table-column prop="id" label="序号" width="80" />
      <el-table-column prop="paperName" label="名称" min-width="180" />
      <el-table-column prop="subjectName" label="学科" width="90" />
      <el-table-column label="状态" width="110">
        <template #default="{ row }">
          <el-tag :type="formatExamAnswerStatusTag(row.status)">{{ formatExamAnswerStatus(row.status) }}</el-tag>
        </template>
      </el-table-column>
      <el-table-column prop="createTime" label="做题时间" width="170" />
      <el-table-column label="操作" align="right" width="110">
        <template #default="{ row }">
          <el-button v-if="row.status === 2" type="primary" link @click.stop="router.push({ path: '/read', query: { id: row.id } })">
            查看试卷
          </el-button>
          <el-button v-else-if="row.status === 1" type="primary" link @click.stop="router.push({ path: '/edit', query: { id: row.id } })">
            批改
          </el-button>
        </template>
      </el-table-column>
    </el-table>

    <el-pagination
      v-if="total > 0"
      class="record-list__pagination"
      layout="prev, pager, next, total"
      :total="total"
      :page-size="query.pageSize"
      :current-page="query.pageIndex"
      @current-change="handlePageChange"
    />

    <aside class="record-list__summary">
      <span>系统判分：{{ selected.systemScore }}</span>
      <span>最终得分：{{ selected.userScore }}</span>
      <span>试卷总分：{{ selected.paperScore }}</span>
      <span>正确题数：{{ selected.questionCorrect }}</span>
      <span>总题数：{{ selected.questionCount }}</span>
      <span>用时：{{ selected.doTime }}</span>
    </aside>
  </section>
</template>

<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import { useRouter } from 'vue-router'
import { getExamRecordPage, type ExamRecordItem } from '@xzs/api-client'
import { formatExamAnswerStatus, formatExamAnswerStatusTag } from '@/utils/format'

const router = useRouter()
const records = ref<ExamRecordItem[]>([])
const total = ref(0)
const loading = ref(false)
const selected = ref<Partial<ExamRecordItem>>({
  systemScore: '0',
  userScore: '0',
  paperScore: '0',
  questionCorrect: 0,
  questionCount: 0,
  doTime: '0'
})
const query = reactive({
  pageIndex: 1,
  pageSize: 10
})

onMounted(loadRecords)

async function loadRecords() {
  loading.value = true
  try {
    const result = await getExamRecordPage(query)
    const page = result.response
    records.value = page?.list ?? []
    total.value = page?.total ?? 0
    query.pageIndex = page?.pageNum ?? query.pageIndex
    selected.value = records.value[0] ?? selected.value
  } finally {
    loading.value = false
  }
}

function handlePageChange(page: number) {
  query.pageIndex = page
  loadRecords()
}

function selectRecord(record: ExamRecordItem) {
  selected.value = record
}
</script>

<style scoped lang="scss">
.record-list {
  display: grid;
  gap: 18px;
  padding: 18px;
  border: 1px solid #e5e7eb;
  border-radius: 6px;
  background: #fff;
}

.record-list__header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
}

.record-list__header h1 {
  margin: 0;
  color: #111827;
  font-size: 22px;
}

.record-list__pagination {
  justify-content: flex-end;
}

.record-list__summary {
  display: grid;
  grid-template-columns: repeat(3, minmax(120px, 1fr));
  gap: 10px;
  color: #475569;
}

@media (max-width: 720px) {
  .record-list__summary {
    grid-template-columns: 1fr;
  }
}
</style>
