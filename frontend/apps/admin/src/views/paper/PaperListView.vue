<template>
  <section class="admin-page" v-loading="loading">
    <header class="admin-page__header">
      <div>
        <h1>试卷列表</h1>
        <p>管理试卷与组题内容。</p>
      </div>
      <el-button type="primary" @click="router.push('/exam/paper/edit')">添加</el-button>
    </header>

    <section class="admin-page__filters">
      <el-input v-model.number="query.id" clearable placeholder="试卷 ID" @keyup.enter="search" />
      <el-select v-model="query.subjectId" clearable placeholder="学科">
        <el-option v-for="item in subjects" :key="item.id" :label="item.name" :value="item.id" />
      </el-select>
      <el-button type="primary" @click="search">查询</el-button>
    </section>

    <el-table :data="papers" border>
      <el-table-column prop="id" label="Id" width="90" />
      <el-table-column label="学科" width="140">
        <template #default="{ row }">{{ subjectName(row.subjectId) }}</template>
      </el-table-column>
      <el-table-column prop="name" label="名称" min-width="240" show-overflow-tooltip />
      <el-table-column prop="questionCount" label="题数" width="90" />
      <el-table-column prop="score" label="分数" width="90" />
      <el-table-column prop="createTime" label="创建时间" width="170" />
      <el-table-column label="操作" width="170" fixed="right">
        <template #default="{ row }">
          <el-button size="small" @click="router.push(`/exam/paper/edit?id=${row.id}`)">编辑</el-button>
          <el-button size="small" type="danger" @click="remove(row.id)">删除</el-button>
        </template>
      </el-table-column>
    </el-table>

    <footer class="admin-page__pagination">
      <el-pagination
        v-model:current-page="query.pageIndex"
        v-model:page-size="query.pageSize"
        background
        layout="total, sizes, prev, pager, next"
        :page-sizes="[10, 20, 50]"
        :total="total"
        @size-change="loadData"
        @current-change="loadData"
      />
    </footer>
  </section>
</template>

<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { useRouter } from 'vue-router'
import {
  deleteAdminExamPaper,
  getAdminExamPaperPage,
  getAdminSubjectPage,
  type AdminExamPaperListItem,
  type AdminSubjectListItem
} from '@xzs/api-client'

const router = useRouter()
const loading = ref(false)
const papers = ref<AdminExamPaperListItem[]>([])
const subjects = ref<AdminSubjectListItem[]>([])
const total = ref(0)
const query = reactive({
  id: null as number | null,
  subjectId: null as number | null,
  pageIndex: 1,
  pageSize: 10
})

onMounted(async () => {
  const subjectResult = await getAdminSubjectPage({ pageIndex: 1, pageSize: 100 })
  subjects.value = subjectResult.response?.list ?? []
  await loadData()
})

function search() {
  query.pageIndex = 1
  loadData()
}

async function loadData() {
  loading.value = true
  try {
    const result = await getAdminExamPaperPage(query)
    const page = result.response
    papers.value = page?.list ?? []
    total.value = page?.total ?? 0
    query.pageIndex = page?.pageNum ?? query.pageIndex
  } finally {
    loading.value = false
  }
}

async function remove(id: number) {
  await ElMessageBox.confirm('确认删除该试卷？', '删除试卷', { type: 'warning' })
  const result = await deleteAdminExamPaper(id)
  ElMessage.success(result.message || '删除成功')
  loadData()
}

function subjectName(subjectId?: number) {
  return subjects.value.find((item) => item.id === subjectId)?.name ?? ''
}
</script>
