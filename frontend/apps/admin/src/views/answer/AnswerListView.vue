<template>
  <section class="admin-page" v-loading="loading">
    <header class="admin-page__header">
      <div>
        <h1>答卷列表</h1>
        <p>查看学生交卷与得分记录。</p>
      </div>
      <el-button type="primary" @click="search">查询</el-button>
    </header>

    <section class="admin-page__filters">
      <el-select v-model="query.subjectId" clearable placeholder="学科">
        <el-option v-for="item in subjects" :key="item.id" :label="item.name" :value="item.id" />
      </el-select>
    </section>

    <el-table :data="answers" border>
      <el-table-column prop="id" label="Id" width="90" />
      <el-table-column prop="paperName" label="试卷名称" min-width="220" show-overflow-tooltip />
      <el-table-column prop="userName" label="用户名称" width="140" />
      <el-table-column label="得分" width="120">
        <template #default="{ row }">{{ row.userScore }} / {{ row.paperScore }}</template>
      </el-table-column>
      <el-table-column label="题目对错" width="120">
        <template #default="{ row }">{{ row.questionCorrect }} / {{ row.questionCount }}</template>
      </el-table-column>
      <el-table-column prop="doTime" label="耗时" width="110" />
      <el-table-column prop="createTime" label="提交时间" width="170" />
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
import {
  getAdminAnswerPage,
  getAdminSubjectPage,
  type AdminAnswerListItem,
  type AdminSubjectListItem
} from '@xzs/api-client'

const loading = ref(false)
const answers = ref<AdminAnswerListItem[]>([])
const subjects = ref<AdminSubjectListItem[]>([])
const total = ref(0)
const query = reactive({
  subjectId: null as number | null,
  pageIndex: 1,
  pageSize: 10
})

onMounted(async () => {
  await loadSubjects()
  await loadData()
})

function search() {
  query.pageIndex = 1
  loadData()
}

async function loadSubjects() {
  const result = await getAdminSubjectPage({ pageIndex: 1, pageSize: 100 })
  subjects.value = result.response?.list ?? []
}

async function loadData() {
  loading.value = true
  try {
    const result = await getAdminAnswerPage(query)
    const page = result.response
    answers.value = page?.list ?? []
    total.value = page?.total ?? 0
    query.pageIndex = page?.pageNum ?? query.pageIndex
  } finally {
    loading.value = false
  }
}
</script>
