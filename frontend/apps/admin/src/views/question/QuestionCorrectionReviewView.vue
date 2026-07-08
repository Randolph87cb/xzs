<template>
  <section class="admin-page" v-loading="loading">
    <header class="admin-page__header">
      <div>
        <h1>改错审核</h1>
        <p>审核学生提交的错题改错，并直接修订为合格版本。</p>
      </div>
      <div class="admin-page__actions">
        <el-button @click="loadData">查询</el-button>
      </div>
    </header>

    <el-form class="admin-page__filters" :model="query" inline>
      <el-form-item label="状态">
        <el-select v-model="query.reviewStatus" clearable placeholder="全部" style="width: 180px">
          <el-option label="待审核" value="SUBMITTED" />
          <el-option label="一审完成" value="REVIEWED_ONCE" />
          <el-option label="二审完成" value="REVIEWED_TWICE" />
        </el-select>
      </el-form-item>
    </el-form>

    <el-table :data="records" border>
      <el-table-column prop="id" label="Id" width="90" />
      <el-table-column label="学生" width="140">
        <template #default="{ row }">{{ row.real_name || row.user_name }}</template>
      </el-table-column>
      <el-table-column label="题干" min-width="260" show-overflow-tooltip>
        <template #default="{ row }">{{ stripHtml(row.title) }}</template>
      </el-table-column>
      <el-table-column label="状态" width="110">
        <template #default="{ row }">{{ statusText(row.review_status) }}</template>
      </el-table-column>
      <el-table-column prop="submit_time" label="提交时间" width="170" />
      <el-table-column label="操作" width="100" fixed="right">
        <template #default="{ row }">
          <el-button size="small" type="primary" @click="openReview(row.id)">审核</el-button>
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

    <el-dialog v-model="reviewVisible" title="改错审核" width="860px">
      <div v-if="detail" class="correction-review">
        <section>
          <h3>题干</h3>
          <QuestionMarkdown :content="detail.title || ''" />
        </section>
        <section class="correction-review__student">
          <h3>学生提交</h3>
          <p><strong>错误原因：</strong>{{ detail.student_wrong_reason }}</p>
          <p><strong>正确思路：</strong>{{ detail.student_correct_thinking }}</p>
        </section>

        <el-form label-width="90px">
          <el-form-item label="审核轮次">
            <el-input-number v-model="reviewForm.reviewRound" :min="1" :max="9" />
          </el-form-item>
          <el-form-item label="错误原因">
            <el-input v-model="reviewForm.reviewedWrongReason" type="textarea" :rows="4" />
          </el-form-item>
          <el-form-item label="正确思路">
            <el-input v-model="reviewForm.reviewedCorrectThinking" type="textarea" :rows="4" />
          </el-form-item>
          <el-form-item label="审核说明">
            <el-input v-model="reviewForm.reviewComment" type="textarea" :rows="2" />
          </el-form-item>
          <el-form-item>
            <el-button type="primary" @click="saveReview">保存审核</el-button>
          </el-form-item>
        </el-form>

        <el-table :data="detail.reviewRecords ?? []" border>
          <el-table-column prop="review_round" label="轮次" width="80" />
          <el-table-column prop="reviewer_name" label="审核人" width="120" />
          <el-table-column prop="after_wrong_reason" label="审核后错误原因" min-width="180" show-overflow-tooltip />
          <el-table-column prop="after_correct_thinking" label="审核后正确思路" min-width="180" show-overflow-tooltip />
          <el-table-column prop="review_comment" label="说明" min-width="160" show-overflow-tooltip />
        </el-table>
      </div>
    </el-dialog>
  </section>
</template>

<script setup lang="ts">
import { reactive, ref } from 'vue'
import { ElMessage } from 'element-plus'
import { QuestionMarkdown } from '@xzs/question-renderer'
import {
  getAdminQuestionCorrection,
  getAdminQuestionCorrectionPage,
  saveAdminQuestionCorrectionReview,
  type AdminQuestionCorrectionItem,
  type AdminQuestionCorrectionPageRequest
} from '@xzs/api-client'

const loading = ref(false)
const reviewVisible = ref(false)
const records = ref<AdminQuestionCorrectionItem[]>([])
const detail = ref<AdminQuestionCorrectionItem | null>(null)
const total = ref(0)
const query = reactive<AdminQuestionCorrectionPageRequest>({
  reviewStatus: null,
  pageIndex: 1,
  pageSize: 10
})
const reviewForm = reactive({
  id: 0,
  reviewRound: 1,
  reviewedWrongReason: '',
  reviewedCorrectThinking: '',
  reviewComment: ''
})

loadData()

async function loadData() {
  loading.value = true
  try {
    const result = await getAdminQuestionCorrectionPage(query)
    records.value = result.response?.list ?? []
    total.value = result.response?.total ?? 0
  } finally {
    loading.value = false
  }
}

async function openReview(id: number) {
  const result = await getAdminQuestionCorrection(id)
  detail.value = result.response ?? null
  if (!detail.value) return
  reviewForm.id = id
  reviewForm.reviewRound = nextRound(detail.value.review_status)
  reviewForm.reviewedWrongReason = detail.value.reviewed_wrong_reason || detail.value.student_wrong_reason || ''
  reviewForm.reviewedCorrectThinking = detail.value.reviewed_correct_thinking || detail.value.student_correct_thinking || ''
  reviewForm.reviewComment = ''
  reviewVisible.value = true
}

async function saveReview() {
  if (!reviewForm.reviewedWrongReason.trim() || !reviewForm.reviewedCorrectThinking.trim()) {
    ElMessage.error('请完整填写错误原因和正确思路')
    return
  }
  const result = await saveAdminQuestionCorrectionReview(reviewForm)
  ElMessage.success(result.message || '改错审核已保存')
  await openReview(reviewForm.id)
  await loadData()
}

function nextRound(status?: string) {
  if (status === 'REVIEWED_ONCE') return 2
  if (status === 'REVIEWED_TWICE') return 2
  return 1
}

function statusText(status?: string) {
  const map: Record<string, string> = {
    SUBMITTED: '待审核',
    REVIEWED_ONCE: '一审完成',
    REVIEWED_TWICE: '二审完成'
  }
  return map[status ?? ''] ?? '未知'
}

function stripHtml(value?: string) {
  return (value ?? '').replace(/<[^>]*>/g, '').slice(0, 120)
}
</script>

<style scoped>
.correction-review {
  display: grid;
  gap: 14px;
}

.correction-review h3,
.correction-review p {
  margin: 0;
}

.correction-review__student {
  display: grid;
  gap: 8px;
  padding: 12px;
  border: 1px solid #e5e7eb;
  background: #f9fafb;
}
</style>
