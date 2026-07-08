<template>
  <section class="admin-page" v-loading="loading">
    <header class="admin-page__header">
      <div>
        <h1>题目质量审核</h1>
        <p>审核并修订题目解析和知识点配置，保留一审、二审记录。</p>
      </div>
      <div class="admin-page__actions">
        <el-button @click="loadData">查询</el-button>
      </div>
    </header>

    <el-form class="admin-page__filters" :model="query" inline>
      <el-form-item label="审核类型">
        <el-select v-model="query.reviewType" clearable placeholder="全部" style="width: 160px" @change="resetAndLoad">
          <el-option label="解析审核" value="ANALYSIS" />
          <el-option label="知识点审核" value="KNOWLEDGE_POINT" />
        </el-select>
      </el-form-item>
      <el-form-item label="审核状态">
        <el-select v-model="query.reviewStatus" clearable placeholder="全部" style="width: 160px" @change="resetAndLoad">
          <el-option label="未审核" value="UNREVIEWED" />
          <el-option label="已审核" value="REVIEWED" />
        </el-select>
      </el-form-item>
      <el-form-item label="关键字">
        <el-input v-model="query.keyword" clearable placeholder="题干/解析关键字" style="width: 220px" @keyup.enter="resetAndLoad" />
      </el-form-item>
      <el-form-item label="学科">
        <el-select v-model="query.subjectId" clearable placeholder="全部" style="width: 180px" @change="handleSubjectChange">
          <el-option v-for="item in subjects" :key="item.id" :label="item.name" :value="item.id" />
        </el-select>
      </el-form-item>
      <el-form-item label="知识点">
        <el-select v-model="query.knowledgePoint" clearable filterable allow-create placeholder="全部" style="width: 260px" @change="resetAndLoad">
          <el-option v-for="item in distribution" :key="item.knowledge_point" :label="item.knowledge_point" :value="item.knowledge_point" />
        </el-select>
      </el-form-item>
    </el-form>

    <section class="review-layout">
      <el-table :data="questions" border class="review-layout__questions">
        <el-table-column prop="id" label="Id" width="90" />
        <el-table-column prop="knowledge_point" label="知识点" width="180" show-overflow-tooltip />
        <el-table-column label="题干" min-width="260" show-overflow-tooltip>
          <template #default="{ row }">{{ stripHtml(row.title) }}</template>
        </el-table-column>
        <el-table-column label="解析审核" width="110">
          <template #default="{ row }">{{ reviewRoundText(row.analysis_review_round) }}</template>
        </el-table-column>
        <el-table-column label="知识点审核" width="120">
          <template #default="{ row }">{{ reviewRoundText(row.knowledge_review_round) }}</template>
        </el-table-column>
        <el-table-column label="操作" width="100" fixed="right">
          <template #default="{ row }">
            <el-button size="small" type="primary" @click="openReview(row.id)">审核</el-button>
          </template>
        </el-table-column>
      </el-table>

      <el-table :data="distribution" border class="review-layout__distribution">
        <el-table-column prop="knowledge_point" label="知识点分布" min-width="180" show-overflow-tooltip />
        <el-table-column prop="question_count" label="题数" width="70" />
        <el-table-column prop="reviewed_count" label="已审" width="70" />
        <el-table-column prop="unreviewed_count" label="未审" width="70" />
      </el-table>
    </section>

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

    <el-dialog v-model="reviewVisible" title="题目审核" width="980px">
      <div v-if="detail" class="review-dialog">
        <section class="review-dialog__preview">
          <h3>题干</h3>
          <QuestionMarkdown :content="detail.title || ''" />
          <h3>当前解析</h3>
          <QuestionMarkdown :content="detail.analyze || ''" />
        </section>

        <el-tabs>
          <el-tab-pane label="解析审核">
            <el-form label-width="90px">
              <el-form-item label="审核轮次">
                <span class="review-dialog__round">{{ reviewRoundText(analysisForm.reviewRound) }}</span>
              </el-form-item>
              <el-form-item label="解析">
                <div class="review-dialog__editor">
                  <el-input v-model="analysisForm.afterValue" type="textarea" :rows="10" />
                  <section class="review-dialog__markdown-preview">
                    <h4>Markdown 预览</h4>
                    <QuestionMarkdown :content="analysisForm.afterValue" />
                  </section>
                </div>
              </el-form-item>
              <el-form-item label="审核说明">
                <el-input v-model="analysisForm.reviewComment" type="textarea" :rows="2" />
              </el-form-item>
              <el-form-item>
                <el-button type="primary" @click="saveAnalysis">保存解析审核</el-button>
              </el-form-item>
            </el-form>
          </el-tab-pane>

          <el-tab-pane label="知识点审核">
            <el-form label-width="90px">
              <el-form-item label="审核轮次">
                <span class="review-dialog__round">{{ reviewRoundText(knowledgeForm.reviewRound) }}</span>
              </el-form-item>
              <el-form-item label="知识点">
                <el-select v-model="knowledgeForm.afterValue" filterable allow-create default-first-option style="width: 100%">
                  <el-option v-for="item in distribution" :key="item.knowledge_point" :label="item.knowledge_point" :value="item.knowledge_point" />
                </el-select>
              </el-form-item>
              <el-form-item label="审核说明">
                <el-input v-model="knowledgeForm.reviewComment" type="textarea" :rows="2" />
              </el-form-item>
              <el-form-item>
                <el-button type="primary" @click="saveKnowledge">保存知识点审核</el-button>
              </el-form-item>
            </el-form>
          </el-tab-pane>

          <el-tab-pane label="审核记录">
            <el-table :data="detail.reviewRecords ?? []" border>
              <el-table-column prop="review_type" label="类型" width="130">
                <template #default="{ row }">{{ row.review_type === 'ANALYSIS' ? '解析' : '知识点' }}</template>
              </el-table-column>
              <el-table-column prop="review_round" label="轮次" width="80" />
              <el-table-column prop="reviewer_name" label="审核人" width="120" />
              <el-table-column prop="after_value" label="审核后内容" min-width="240" show-overflow-tooltip />
              <el-table-column prop="review_comment" label="说明" min-width="180" show-overflow-tooltip />
            </el-table>
          </el-tab-pane>
        </el-tabs>
      </div>
    </el-dialog>
  </section>
</template>

<script setup lang="ts">
import { reactive, ref } from 'vue'
import { ElMessage } from 'element-plus'
import { QuestionMarkdown } from '@xzs/question-renderer'
import {
  getAdminKnowledgePointDistribution,
  getAdminQuestionReview,
  getAdminQuestionReviewPage,
  getAdminSubjectPage,
  saveAdminQuestionAnalysisReview,
  saveAdminQuestionKnowledgeReview,
  type AdminKnowledgePointDistributionItem,
  type AdminQuestionReviewDetail,
  type AdminQuestionReviewListItem,
  type AdminQuestionReviewPageRequest,
  type AdminSubjectListItem
} from '@xzs/api-client'

const loading = ref(false)
const reviewVisible = ref(false)
const subjects = ref<AdminSubjectListItem[]>([])
const questions = ref<AdminQuestionReviewListItem[]>([])
const distribution = ref<AdminKnowledgePointDistributionItem[]>([])
const total = ref(0)
const detail = ref<AdminQuestionReviewDetail | null>(null)

const query = reactive<AdminQuestionReviewPageRequest>({
  subjectId: null,
  knowledgePoint: null,
  reviewType: null,
  reviewStatus: 'UNREVIEWED',
  keyword: '',
  pageIndex: 1,
  pageSize: 10
})

const analysisForm = reactive({
  questionId: 0,
  reviewRound: 1,
  afterValue: '',
  reviewComment: ''
})

const knowledgeForm = reactive({
  questionId: 0,
  reviewRound: 1,
  afterValue: '',
  reviewComment: ''
})

loadSubjects()
loadData()

async function loadSubjects() {
  const result = await getAdminSubjectPage({ pageIndex: 1, pageSize: 100 })
  subjects.value = result.response?.list ?? []
}

async function loadData() {
  loading.value = true
  try {
    const result = await getAdminQuestionReviewPage(query)
    questions.value = result.response?.list ?? []
    total.value = result.response?.total ?? 0
    if (query.subjectId) {
      await loadDistribution(query.subjectId)
    } else {
      distribution.value = []
    }
  } finally {
    loading.value = false
  }
}

async function handleSubjectChange() {
  query.knowledgePoint = null
  query.pageIndex = 1
  await loadData()
}

async function resetAndLoad() {
  query.pageIndex = 1
  await loadData()
}

async function loadDistribution(subjectId: number) {
  const result = await getAdminKnowledgePointDistribution(subjectId)
  distribution.value = result.response ?? []
}

async function openReview(questionId: number) {
  const result = await getAdminQuestionReview(questionId)
  detail.value = result.response ?? null
  if (!detail.value) return
  analysisForm.questionId = questionId
  analysisForm.reviewRound = Math.max(1, (detail.value.analysis_review_round ?? 0) + 1)
  analysisForm.afterValue = detail.value.analyze ?? ''
  analysisForm.reviewComment = ''
  knowledgeForm.questionId = questionId
  knowledgeForm.reviewRound = Math.max(1, (detail.value.knowledge_review_round ?? 0) + 1)
  knowledgeForm.afterValue = detail.value.knowledge_point ?? ''
  knowledgeForm.reviewComment = ''
  if (detail.value.subject_id) {
    await loadDistribution(detail.value.subject_id)
  }
  reviewVisible.value = true
}

async function saveAnalysis() {
  if (!analysisForm.afterValue.trim()) {
    ElMessage.error('解析不能为空')
    return
  }
  const result = await saveAdminQuestionAnalysisReview({
    questionId: analysisForm.questionId,
    afterValue: analysisForm.afterValue,
    reviewComment: analysisForm.reviewComment
  })
  ElMessage.success(result.message || '解析审核已保存')
  await refreshCurrentReview()
  await loadData()
}

async function saveKnowledge() {
  if (!knowledgeForm.afterValue.trim()) {
    ElMessage.error('知识点不能为空')
    return
  }
  const result = await saveAdminQuestionKnowledgeReview({
    questionId: knowledgeForm.questionId,
    afterValue: knowledgeForm.afterValue,
    reviewComment: knowledgeForm.reviewComment
  })
  ElMessage.success(result.message || '知识点审核已保存')
  await refreshCurrentReview()
  await loadData()
}

async function refreshCurrentReview() {
  if (!detail.value?.id) return
  await openReview(detail.value.id)
}

function stripHtml(value?: string) {
  return (value ?? '').replace(/<[^>]*>/g, '').slice(0, 120)
}

function reviewRoundText(round?: number) {
  return round ? `${round}审` : '未审'
}
</script>

<style scoped>
.review-layout {
  display: grid;
  grid-template-columns: minmax(0, 1fr) 360px;
  gap: 12px;
}

.review-layout__questions,
.review-layout__distribution {
  min-width: 0;
}

.review-dialog {
  display: grid;
  gap: 12px;
}

.review-dialog__preview {
  display: grid;
  gap: 8px;
  padding-bottom: 8px;
  border-bottom: 1px solid #e5e7eb;
}

.review-dialog__preview h3 {
  margin: 0;
  font-size: 15px;
}

.review-dialog__round {
  color: #374151;
}

.review-dialog__editor {
  display: grid;
  grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
  gap: 12px;
  width: 100%;
}

.review-dialog__markdown-preview {
  min-height: 240px;
  padding: 10px;
  border: 1px solid #dcdfe6;
  border-radius: 4px;
  overflow: auto;
}

.review-dialog__markdown-preview h4 {
  margin: 0 0 8px;
  color: #606266;
  font-size: 14px;
  font-weight: 500;
}
</style>
