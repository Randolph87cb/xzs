<template>
  <section class="paper-list">
    <header class="paper-list__header">
      <h1>试卷中心</h1>
      <el-radio-group v-model="query.paperType" size="small" @change="loadPapers">
        <el-radio-button :label="1">固定试卷</el-radio-button>
        <el-radio-button :label="4">时段试卷</el-radio-button>
      </el-radio-group>
    </header>

    <el-tabs v-model="activeSubjectId" tab-position="left" class="paper-list__tabs" @tab-change="handleSubjectChange">
      <el-tab-pane v-for="subject in subjects" :key="subject.id" :name="String(subject.id)" :label="subject.name">
        <el-table v-loading="loading" :data="papers" row-key="id">
          <el-table-column prop="id" label="序号" width="90" />
          <el-table-column prop="name" label="名称" min-width="220" />
          <el-table-column label="操作" align="right" width="120">
            <template #default="{ row }">
              <el-button type="primary" link @click="router.push({ path: '/do', query: { id: row.id } })">开始答题</el-button>
            </template>
          </el-table-column>
        </el-table>

        <el-pagination
          v-if="total > 0"
          class="paper-list__pagination"
          layout="prev, pager, next, total"
          :total="total"
          :page-size="query.pageSize"
          :current-page="query.pageIndex"
          @current-change="handlePageChange"
        />
      </el-tab-pane>
    </el-tabs>
  </section>
</template>

<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import { useRouter } from 'vue-router'
import { ElMessage } from 'element-plus'
import { getExamPaperPage, getSubjectList, type ExamPaperListItem, type SubjectItem } from '@xzs/api-client'

const router = useRouter()
const subjects = ref<SubjectItem[]>([])
const papers = ref<ExamPaperListItem[]>([])
const total = ref(0)
const loading = ref(false)
const activeSubjectId = ref('')
const query = reactive({
  paperType: 1,
  subjectId: 0,
  pageIndex: 1,
  pageSize: 10
})

onMounted(loadSubjects)

async function loadSubjects() {
  const result = await getSubjectList()
  subjects.value = result.response ?? []

  if (subjects.value.length === 0) {
    ElMessage.warning('暂无可用科目')
    return
  }

  query.subjectId = subjects.value[0].id
  activeSubjectId.value = String(query.subjectId)
  await loadPapers()
}

async function loadPapers() {
  if (!query.subjectId) {
    return
  }

  loading.value = true
  try {
    const result = await getExamPaperPage(query)
    const page = result.response
    papers.value = page?.list ?? []
    total.value = page?.total ?? 0
    query.pageIndex = page?.pageNum ?? query.pageIndex
  } finally {
    loading.value = false
  }
}

function handleSubjectChange(name: string | number) {
  query.subjectId = Number(name)
  query.pageIndex = 1
  loadPapers()
}

function handlePageChange(page: number) {
  query.pageIndex = page
  loadPapers()
}
</script>

<style scoped lang="scss">
.paper-list {
  display: grid;
  gap: 18px;
}

.paper-list__header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
}

.paper-list__header h1 {
  margin: 0;
  color: #111827;
  font-size: 22px;
}

.paper-list__tabs {
  min-height: 360px;
  padding: 18px;
  border: 1px solid #e5e7eb;
  border-radius: 6px;
  background: #fff;
}

.paper-list__pagination {
  justify-content: flex-end;
  margin-top: 18px;
}

@media (max-width: 720px) {
  .paper-list__header {
    align-items: stretch;
    flex-direction: column;
  }
}
</style>
