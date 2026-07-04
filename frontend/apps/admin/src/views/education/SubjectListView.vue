<template>
  <section class="admin-page" v-loading="loading">
    <header class="admin-page__header">
      <div>
        <h1>学科列表</h1>
        <p>管理考试系统中的学科基础数据。</p>
      </div>
      <el-button type="primary" @click="loadData">查询</el-button>
    </header>

    <el-table :data="subjects" border>
      <el-table-column prop="id" label="Id" width="120" />
      <el-table-column prop="name" label="学科" min-width="180" />
      <el-table-column prop="levelName" label="年级" min-width="160" />
      <el-table-column prop="level" label="年级编码" width="120" />
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
import { getAdminSubjectPage, type AdminSubjectListItem } from '@xzs/api-client'

const loading = ref(false)
const subjects = ref<AdminSubjectListItem[]>([])
const total = ref(0)
const query = reactive({
  pageIndex: 1,
  pageSize: 10
})

onMounted(loadData)

async function loadData() {
  loading.value = true
  try {
    const result = await getAdminSubjectPage(query)
    const page = result.response
    subjects.value = page?.list ?? []
    total.value = page?.total ?? 0
    query.pageIndex = page?.pageNum ?? query.pageIndex
  } finally {
    loading.value = false
  }
}
</script>
