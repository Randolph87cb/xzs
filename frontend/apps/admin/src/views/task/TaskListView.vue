<template>
  <section class="admin-page" v-loading="loading">
    <header class="admin-page__header">
      <div>
        <h1>任务列表</h1>
        <p>管理下发给学生的试卷任务。</p>
      </div>
      <el-button type="primary" @click="router.push('/task/edit')">添加</el-button>
    </header>

    <el-table :data="tasks" border>
      <el-table-column prop="id" label="Id" width="90" />
      <el-table-column prop="title" label="标题" min-width="220" show-overflow-tooltip />
      <el-table-column prop="createUserName" label="发送人" width="140" />
      <el-table-column prop="createTime" label="创建时间" width="170" />
      <el-table-column label="操作" width="170" fixed="right">
        <template #default="{ row }">
          <el-button size="small" @click="router.push(`/task/edit?id=${row.id}`)">编辑</el-button>
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
import { deleteAdminTask, getAdminTaskPage, type AdminTaskListItem } from '@xzs/api-client'

const router = useRouter()
const loading = ref(false)
const tasks = ref<AdminTaskListItem[]>([])
const total = ref(0)
const query = reactive({ pageIndex: 1, pageSize: 10 })

onMounted(loadData)

async function loadData() {
  loading.value = true
  try {
    const result = await getAdminTaskPage(query)
    const page = result.response
    tasks.value = page?.list ?? []
    total.value = page?.total ?? 0
    query.pageIndex = page?.pageNum ?? query.pageIndex
  } finally {
    loading.value = false
  }
}

async function remove(id: number) {
  await ElMessageBox.confirm('确认删除该任务？', '删除任务', { type: 'warning' })
  const result = await deleteAdminTask(id)
  ElMessage.success(result.message || '删除成功')
  loadData()
}
</script>
