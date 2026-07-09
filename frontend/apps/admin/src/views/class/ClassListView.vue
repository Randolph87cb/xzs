<template>
  <section class="admin-page" v-loading="loading">
    <header class="admin-page__header">
      <div>
        <h1>班级列表</h1>
        <p>维护班级和负责老师。</p>
      </div>
      <el-button type="primary" @click="router.push('/class/edit')">添加</el-button>
    </header>

    <section class="admin-page__filters">
      <el-input v-model="query.name" clearable placeholder="班级名称" @keyup.enter="search" />
      <el-button type="primary" @click="search">查询</el-button>
    </section>

    <el-table :data="classes" border>
      <el-table-column prop="id" label="Id" width="90" />
      <el-table-column prop="name" label="班级名称" min-width="180" />
      <el-table-column prop="gradeLevel" label="年级" width="100" />
      <el-table-column prop="teacherName" label="负责老师" min-width="150" />
      <el-table-column label="状态" width="90">
        <template #default="{ row }">
          <el-tag :type="row.status === 1 ? 'success' : 'info'">{{ row.status === 1 ? '启用' : '禁用' }}</el-tag>
        </template>
      </el-table-column>
      <el-table-column prop="createTime" label="创建时间" width="170" />
      <el-table-column label="操作" width="150" fixed="right">
        <template #default="{ row }">
          <el-button size="small" @click="router.push(`/class/edit?id=${row.id}`)">编辑</el-button>
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
import { deleteAdminClass, getAdminClassPage, type AdminClassListItem } from '@xzs/api-client'

const router = useRouter()
const loading = ref(false)
const classes = ref<AdminClassListItem[]>([])
const total = ref(0)
const query = reactive({
  name: '',
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
    const result = await getAdminClassPage(query)
    const page = result.response
    classes.value = page?.list ?? []
    total.value = page?.total ?? 0
    query.pageIndex = page?.pageNum ?? query.pageIndex
  } finally {
    loading.value = false
  }
}

async function remove(id: number) {
  await ElMessageBox.confirm('确认删除该班级？', '删除班级', { type: 'warning' })
  const result = await deleteAdminClass(id)
  ElMessage.success(result.message || '删除成功')
  loadData()
}
</script>
