<template>
  <section class="admin-page" v-loading="loading">
    <header class="admin-page__header">
      <div>
        <h1>题目列表</h1>
        <p>查看题库题目，进入 Vue 3 富文本编辑闭环。</p>
      </div>
      <div class="admin-page__actions">
        <el-button data-testid="question-search" @click="loadData">查询</el-button>
        <el-button data-testid="question-add" type="primary" @click="router.push('/exam/question/edit')">添加题目</el-button>
      </div>
    </header>

    <el-form class="admin-page__filters" :model="query" inline>
      <el-form-item label="题目 ID">
        <el-input v-model.number="query.id" clearable />
      </el-form-item>
      <el-form-item label="题型">
        <el-select v-model="query.questionType" clearable placeholder="全部" style="width: 150px">
          <el-option v-for="item in questionTypes" :key="item.value" :label="item.label" :value="item.value" />
        </el-select>
      </el-form-item>
      <el-form-item label="知识点">
        <el-input v-model="query.knowledgePoint" data-testid="question-filter-knowledge-point" clearable />
      </el-form-item>
    </el-form>

    <el-table :data="questions" border>
      <el-table-column prop="id" label="Id" width="90" />
      <el-table-column prop="questionType" label="题型" width="100">
        <template #default="{ row }">{{ questionTypeText(row.questionType) }}</template>
      </el-table-column>
      <el-table-column prop="knowledgePoint" label="知识点" width="140" />
      <el-table-column prop="shortTitle" label="题干" min-width="240" show-overflow-tooltip />
      <el-table-column prop="score" label="分数" width="80" />
      <el-table-column prop="difficult" label="难度" width="80" />
      <el-table-column prop="createTime" label="创建时间" width="170" />
      <el-table-column label="操作" width="220" fixed="right">
        <template #default="{ row }">
          <el-button :data-testid="`question-preview-${row.id}`" size="small" @click="previewQuestion(row.id)">预览</el-button>
          <el-button
            :data-testid="`question-edit-${row.id}`"
            size="small"
            type="primary"
            @click="router.push({ path: '/exam/question/edit', query: { id: row.id } })"
          >
            编辑
          </el-button>
          <el-button size="small" type="danger" @click="removeQuestion(row.id)">删除</el-button>
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

    <el-dialog v-model="previewVisible" title="题目预览" width="760px">
      <div v-if="preview" class="question-preview">
        <QuestionMarkdown :content="preview.title" />
        <ol v-if="preview.items?.length" class="question-preview__items">
          <li v-for="item in preview.items" :key="item.prefix">
            <strong>{{ item.prefix }}.</strong>
            <QuestionMarkdown :content="item.content" inline />
          </li>
        </ol>
        <h3>解析</h3>
        <QuestionMarkdown :content="preview.analyze" />
      </div>
    </el-dialog>
  </section>
</template>

<script setup lang="ts">
import { reactive, ref } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { QuestionMarkdown } from '@xzs/question-renderer'
import { useRouter } from 'vue-router'
import {
  deleteAdminQuestion,
  getAdminQuestion,
  getAdminQuestionPage,
  type AdminQuestionEditModel,
  type AdminQuestionListItem,
  type AdminQuestionPageRequest
} from '@xzs/api-client'

const router = useRouter()
const loading = ref(false)
const questions = ref<AdminQuestionListItem[]>([])
const total = ref(0)
const previewVisible = ref(false)
const preview = ref<AdminQuestionEditModel | null>(null)
const query = reactive<AdminQuestionPageRequest>({
  id: null,
  questionType: null,
  subjectId: null,
  knowledgePoint: null,
  pageIndex: 1,
  pageSize: 10
})
const questionTypes = [
  { value: 1, label: '单选题' },
  { value: 2, label: '多选题' },
  { value: 3, label: '判断题' },
  { value: 4, label: '填空题' },
  { value: 5, label: '简答题' }
]

loadData()

async function loadData() {
  loading.value = true
  try {
    const result = await getAdminQuestionPage(query)
    const page = result.response
    questions.value = page?.list ?? []
    total.value = page?.total ?? 0
    query.pageIndex = page?.pageNum ?? query.pageIndex
  } finally {
    loading.value = false
  }
}

async function previewQuestion(id: number) {
  const result = await getAdminQuestion(id)
  preview.value = result.response ?? null
  previewVisible.value = true
}

async function removeQuestion(id: number) {
  await ElMessageBox.confirm('确认删除该题目？', '删除题目', { type: 'warning' })
  const result = await deleteAdminQuestion(id)
  ElMessage.success(result.message || '删除成功')
  loadData()
}

function questionTypeText(type: number) {
  return questionTypes.find((item) => item.value === type)?.label ?? '-'
}
</script>
