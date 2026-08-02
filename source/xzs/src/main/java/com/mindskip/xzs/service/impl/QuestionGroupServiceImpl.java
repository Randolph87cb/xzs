package com.mindskip.xzs.service.impl;

import com.github.pagehelper.PageHelper;
import com.github.pagehelper.PageInfo;
import com.mindskip.xzs.domain.Question;
import com.mindskip.xzs.domain.QuestionGroup;
import com.mindskip.xzs.domain.TextContent;
import com.mindskip.xzs.domain.enums.QuestionGroupTypeEnum;
import com.mindskip.xzs.domain.question.QuestionGroupObject;
import com.mindskip.xzs.repository.QuestionGroupMapper;
import com.mindskip.xzs.repository.QuestionMapper;
import com.mindskip.xzs.service.QuestionGroupService;
import com.mindskip.xzs.service.QuestionService;
import com.mindskip.xzs.service.SubjectService;
import com.mindskip.xzs.service.TextContentService;
import com.mindskip.xzs.utility.DateTimeUtil;
import com.mindskip.xzs.utility.ExamUtil;
import com.mindskip.xzs.utility.JsonUtil;
import com.mindskip.xzs.viewmodel.admin.question.QuestionEditRequestVM;
import com.mindskip.xzs.viewmodel.admin.questiongroup.QuestionGroupEditRequestVM;
import com.mindskip.xzs.viewmodel.admin.questiongroup.QuestionGroupPageRequestVM;
import com.mindskip.xzs.viewmodel.admin.questiongroup.QuestionGroupResponseVM;
import org.apache.commons.lang3.StringUtils;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.Date;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;

@Service
public class QuestionGroupServiceImpl extends BaseServiceImpl<QuestionGroup> implements QuestionGroupService {
    private final QuestionGroupMapper questionGroupMapper;
    private final QuestionMapper questionMapper;
    private final QuestionService questionService;
    private final TextContentService textContentService;
    private final SubjectService subjectService;

    @Autowired
    public QuestionGroupServiceImpl(QuestionGroupMapper questionGroupMapper, QuestionMapper questionMapper,
                                    QuestionService questionService, TextContentService textContentService,
                                    SubjectService subjectService) {
        super(questionGroupMapper);
        this.questionGroupMapper = questionGroupMapper;
        this.questionMapper = questionMapper;
        this.questionService = questionService;
        this.textContentService = textContentService;
        this.subjectService = subjectService;
    }

    @Override
    public PageInfo<QuestionGroupResponseVM> page(QuestionGroupPageRequestVM requestVM) {
        PageInfo<QuestionGroup> page = PageHelper.startPage(requestVM.getPageIndex(), requestVM.getPageSize(), "id desc")
                .doSelectPageInfo(() -> questionGroupMapper.page(requestVM));
        PageInfo<QuestionGroupResponseVM> result = new PageInfo<>();
        result.setPageNum(page.getPageNum());
        result.setPageSize(page.getPageSize());
        result.setPages(page.getPages());
        result.setTotal(page.getTotal());
        result.setList(page.getList().stream().map(this::toResponse).collect(Collectors.toList()));
        return result;
    }

    @Override
    @Transactional
    public QuestionGroup save(QuestionGroupEditRequestVM model, Integer userId) {
        validate(model);
        Date now = new Date();
        QuestionGroup group = model.getId() == null ? new QuestionGroup() : questionGroupMapper.selectByPrimaryKey(model.getId());
        if (model.getId() != null && (group == null || Boolean.TRUE.equals(group.getDeleted()))) {
            throw new IllegalArgumentException("题组不存在或已删除");
        }
        if (group.getId() == null) {
            TextContent content = new TextContent(groupContent(model.getTitle()), now);
            textContentService.insertByFilter(content);
            group.setInfoTextContentId(content.getId());
            group.setCreateUser(userId);
            group.setCreateTime(now);
            group.setDeleted(false);
        } else {
            TextContent content = textContentService.selectById(group.getInfoTextContentId());
            content.setContent(groupContent(model.getTitle()));
            textContentService.updateByIdFilter(content);
        }
        group.setGroupType(model.getGroupType());
        group.setSubjectId(model.getSubjectId());
        group.setGradeLevel(subjectService.levelBySubjectId(model.getSubjectId()));
        group.setDifficult(model.getDifficult());
        group.setKnowledgePoint(StringUtils.defaultIfBlank(model.getKnowledgePoint(), "综合"));
        group.setGroupCode(model.getGroupCode());
        group.setImportBatch(model.getImportBatch());
        group.setImportSource(model.getImportSource());
        group.setImportParentOrder(model.getImportParentOrder());
        group.setStatus(model.getStatus() == null ? 1 : model.getStatus());
        if (group.getId() == null) {
            questionGroupMapper.insertSelective(group);
        } else {
            questionGroupMapper.updateByPrimaryKeySelective(group);
        }

        List<Question> savedQuestions = new ArrayList<>();
        if (model.getQuestionItems() != null) {
            for (QuestionEditRequestVM item : model.getQuestionItems()) {
                Question question = item.getId() == null
                        ? questionService.insertFullQuestion(item, userId)
                        : questionService.updateFullQuestionFromGroup(item, group.getId());
                savedQuestions.add(question);
            }
        }
        questionMapper.clearQuestionGroupAssignments(group.getId());
        for (int i = 0; i < savedQuestions.size(); i++) {
            QuestionEditRequestVM item = model.getQuestionItems().get(i);
            int order = item.getGroupItemOrder() == null ? i + 1 : item.getGroupItemOrder();
            questionMapper.updateQuestionGroupAssignment(savedQuestions.get(i).getId(), group.getId(), order);
        }
        return group;
    }

    private void validate(QuestionGroupEditRequestVM model) {
        if (QuestionGroupTypeEnum.fromCode(model.getGroupType()) == null) {
            throw new IllegalArgumentException("题组类型无效");
        }
        if (subjectService.selectById(model.getSubjectId()) == null) {
            throw new IllegalArgumentException("科目不存在");
        }
        List<QuestionEditRequestVM> items = model.getQuestionItems();
        boolean active = model.getStatus() == null || model.getStatus() == 1;
        if (active && (items == null || items.isEmpty())) {
            throw new IllegalArgumentException("有效题组至少需要一个子题");
        }
        Set<Integer> ids = new HashSet<>();
        Set<Integer> orders = new HashSet<>();
        if (items == null) { return; }
        for (int index = 0; index < items.size(); index++) {
            QuestionEditRequestVM item = items.get(index);
            if (!model.getSubjectId().equals(item.getSubjectId())) {
                throw new IllegalArgumentException("题组与子题必须属于同一科目");
            }
            int order = item.getGroupItemOrder() == null ? index + 1 : item.getGroupItemOrder();
            if (order < 1 || !orders.add(order)) {
                throw new IllegalArgumentException("组内顺序必须为不重复的正整数");
            }
            if (item.getId() != null) {
                if (!ids.add(item.getId())) {
                    throw new IllegalArgumentException("题组不能包含重复子题");
                }
                Question existing = questionMapper.selectByPrimaryKey(item.getId());
                if (existing == null || Boolean.TRUE.equals(existing.getDeleted())) {
                    throw new IllegalArgumentException("子题不存在或已删除：" + item.getId());
                }
                if (!model.getSubjectId().equals(existing.getSubjectId())) {
                    throw new IllegalArgumentException("题组与子题必须属于同一科目");
                }
                if (existing.getQuestionGroupId() != null && !existing.getQuestionGroupId().equals(model.getId())) {
                    throw new IllegalArgumentException("子题已属于其它题组：" + item.getId());
                }
            }
        }
        for (int expectedOrder = 1; expectedOrder <= items.size(); expectedOrder++) {
            if (!orders.contains(expectedOrder)) {
                throw new IllegalArgumentException("组内顺序必须从1开始连续编号");
            }
        }
    }

    @Override
    public QuestionGroupResponseVM selectFullById(Integer id) {
        QuestionGroup group = questionGroupMapper.selectByPrimaryKey(id);
        return group == null ? null : toResponse(group);
    }

    @Override
    public List<QuestionGroup> selectActiveBySubjectId(Integer subjectId) {
        return questionGroupMapper.selectActiveBySubjectId(subjectId);
    }

    @Override
    @Transactional
    public void softDelete(Integer id) {
        QuestionGroup group = questionGroupMapper.selectByPrimaryKey(id);
        if (group == null) { return; }
        group.setDeleted(true);
        questionGroupMapper.updateByPrimaryKeySelective(group);
    }

    private QuestionGroupResponseVM toResponse(QuestionGroup group) {
        QuestionGroupResponseVM vm = new QuestionGroupResponseVM();
        vm.setId(group.getId()); vm.setGroupType(group.getGroupType()); vm.setSubjectId(group.getSubjectId());
        vm.setGradeLevel(group.getGradeLevel()); vm.setDifficult(group.getDifficult()); vm.setKnowledgePoint(group.getKnowledgePoint());
        vm.setGroupCode(group.getGroupCode()); vm.setImportBatch(group.getImportBatch()); vm.setImportSource(group.getImportSource());
        vm.setImportParentOrder(group.getImportParentOrder()); vm.setStatus(group.getStatus());
        vm.setCreateTime(DateTimeUtil.dateFormat(group.getCreateTime()));
        TextContent content = textContentService.selectById(group.getInfoTextContentId());
        if (content != null) { vm.setTitle(JsonUtil.toJsonObject(content.getContent(), QuestionGroupObject.class).getTitleContent()); }
        List<Question> questions = questionMapper.selectByQuestionGroupId(group.getId());
        List<QuestionEditRequestVM> items = questions.stream().map(questionService::getQuestionEditRequestVM).collect(Collectors.toList());
        vm.setQuestionItems(items);
        vm.setQuestionCount(items.size());
        vm.setTotalScore(ExamUtil.scoreToVM(questions.stream().mapToInt(Question::getScore).sum()));
        return vm;
    }

    private String groupContent(String title) {
        QuestionGroupObject object = new QuestionGroupObject();
        object.setTitleContent(title);
        return JsonUtil.toJsonStr(object);
    }
}
