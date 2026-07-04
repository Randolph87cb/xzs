<template>
  <section class="admin-page" v-loading="loading">
    <header class="admin-page__header">
      <div>
        <h1>用户日志</h1>
        <p>查看用户操作动态。</p>
      </div>
      <el-button type="primary" @click="search">查询</el-button>
    </header>

    <section class="admin-page__filters">
      <el-input v-model.number="query.userId" clearable placeholder="用户 Id" @keyup.enter="search" />
      <el-input v-model="query.userName" clearable placeholder="用户名" @keyup.enter="search" />
    </section>

    <el-table :data="logs" border>
      <el-table-column prop="id" label="Id" width="90" />
      <el-table-column prop="userName" label="用户名" width="150" />
      <el-table-column prop="realName" label="真实姓名" width="150" />
      <el-table-column prop="content" label="动态" min-width="260" show-overflow-tooltip />
      <el-table-column prop="createTime" label="创建时间" width="170" />
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
import { useRoute } from 'vue-router'
import { getAdminUserEventPage, type AdminUserEventListItem } from '@xzs/api-client'

const route = useRoute()
const loading = ref(false)
const logs = ref<AdminUserEventListItem[]>([])
const total = ref(0)
const query = reactive({
  userId: Number(route.query.userId || 0) || null,
  userName: '',
  pageIndex: 1,
  pageSize: 10
})

onMounted(loadData)

function search() {
  query.pageIndex = 1
  loadData()
}

async function loadData() {
  loading.value = true
  try {
    const result = await getAdminUserEventPage(query)
    const page = result.response
    logs.value = page?.list ?? []
    total.value = page?.total ?? 0
    query.pageIndex = page?.pageNum ?? query.pageIndex
  } finally {
    loading.value = false
  }
}
</script>
