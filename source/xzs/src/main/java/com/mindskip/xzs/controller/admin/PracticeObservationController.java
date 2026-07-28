package com.mindskip.xzs.controller.admin;

import com.mindskip.xzs.base.BaseApiController;
import com.mindskip.xzs.base.RestResponse;
import com.mindskip.xzs.domain.User;
import com.mindskip.xzs.service.ClassScopeService;
import com.mindskip.xzs.service.PracticeObservationService;
import com.mindskip.xzs.viewmodel.admin.practice.PracticeObservationRequestVM;
import com.mindskip.xzs.viewmodel.admin.practice.PracticeObservationResponseVM;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestMethod;
import org.springframework.web.bind.annotation.RestController;

import java.time.LocalDate;

@RestController("AdminPracticeObservationController")
@RequestMapping(value = "/api/admin/practiceObservation")
public class PracticeObservationController extends BaseApiController {

    private final PracticeObservationService practiceObservationService;
    private final ClassScopeService classScopeService;

    @Autowired
    public PracticeObservationController(PracticeObservationService practiceObservationService,
                                         ClassScopeService classScopeService) {
        this.practiceObservationService = practiceObservationService;
        this.classScopeService = classScopeService;
    }

    @RequestMapping(value = "/index", method = RequestMethod.POST)
    public RestResponse<PracticeObservationResponseVM> index(@RequestBody(required = false) PracticeObservationRequestVM model) {
        PracticeObservationRequestVM request = model == null ? new PracticeObservationRequestVM() : model;
        User currentUser = getCurrentUser();
        if (classScopeService.isTeacher(currentUser)) {
            request.setClassIds(classScopeService.teacherClassIds(currentUser));
        }
        return RestResponse.ok(practiceObservationService.observe(request, LocalDate.now()));
    }
}
